import Foundation
import Observation

/// Errors surfaced by the automatic DeepSeekSync setup flow.
public enum DeepSeekSyncSetupError: Error, LocalizedError {
    case downloadFailed(String)
    case extractionFailed(String)
    case moduleNotFound
    case destinationFailed(String)
    case setupFailed(Int32)
    case launcherMissing(String)

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason):
            return "Download failed: " + reason
        case .extractionFailed(let reason):
            return "Extraction failed: " + reason
        case .moduleNotFound:
            return "DeepSeekSync module was not found in the downloaded archive"
        case .destinationFailed(let reason):
            return "Could not install the module: " + reason
        case .setupFailed(let code):
            return "Runtime setup failed (setup-runtime.sh exited " + String(code) + ")"
        case .launcherMissing(let path):
            return "deepseek-sync launcher is missing at " + path
        }
    }
}

/// One-click setup of the DeepSeekSync CLI (DR-001 module):
///
/// 1. download the source-only archive (DeepSeekSync/ is ~a few MB - the big
///    Node runtime / Playwright / Chromium are gitignored),
/// 2. extract it into ~/Library/Application Support/APIMeter/DeepSeekSync,
/// 3. run the module's setup-runtime.sh (downloads portable Node, installs
///    npm deps, downloads Chromium - idempotent, ~450MB first time),
/// 4. point AppSettings.syncToolPath at it and open the headed login window.
///
/// Fully offline fallback stays available: the manual path in Settings > Data.
@MainActor
@Observable
public final class DeepSeekSyncInstaller {
    public enum Phase: Equatable {
        case idle
        case downloading(Double)
        case extracting
        case settingUp
        case openingLogin
        case done
        case cancelled
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// Rolling tail of the setup log (download/extraction errors, npm output...).
    public private(set) var logTail: String = ""

    private let settings: AppSettings
    private var setupProcess: Process?
    private var loginProcess: Process?
    private var cancelled = false

    public init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - State helpers

    /// True when a syncToolPath is set and the CLI launcher exists there.
    public var isConfigured: Bool {
        guard let path = settings.syncToolPath, !path.isEmpty else { return false }
        return FileManager.default.isExecutableFile(atPath: path + "/deepseek-sync")
            || FileManager.default.fileExists(atPath: path + "/deepseek-sync")
    }

    public var isActive: Bool {
        switch phase {
        case .downloading, .extracting, .settingUp, .openingLogin:
            return true
        default:
            return false
        }
    }

    /// One-shot entry point. Safe to call again after failure/cancel.
    public func install() async {
        guard !isActive else { return }
        cancelled = false
        logTail = ""
        phase = .downloading(0)
        appendLog("开始自动安装 DeepSeekSync (v" + DeepSeekSyncInstaller.releaseVersion + ")...")
        do {
            let zipURL = try await downloadArchive()
            try Task.checkCancellation()
            guard !cancelled else { return }

            phase = .extracting
            appendLog("解压模块...")
            let moduleDir = try await extractModule(from: zipURL)
            let dest = Self.moduleDestination()
            try prepareDestination(dest)
            try FileManager.default.moveItem(at: moduleDir, to: dest)
            Self.stripQuarantine(at: dest)
            appendLog("模块安装到 " + dest.path)

            phase = .settingUp
            appendLog("安装运行时（Node + Playwright + Chromium，首次约 450MB，需几分钟）...")
            try await runSetupScript(in: dest)
            if cancelled { return }

            settings.syncToolPath = dest.path
            appendLog("已配置 DeepSeekSync 路径。")

            phase = .openingLogin
            try launchLogin(in: dest)
            phase = .done
        } catch is CancellationError {
            phase = .cancelled
            appendLog("已取消。")
        } catch let error as DeepSeekSyncSetupError {
            if cancelled {
                phase = .cancelled
            } else {
                phase = .failed(error.localizedDescription)
                appendLog("安装失败：" + error.localizedDescription)
            }
        } catch {
            if cancelled {
                phase = .cancelled
            } else {
                phase = .failed(error.localizedDescription)
                appendLog("安装失败：" + error.localizedDescription)
            }
        }
    }

    /// Best-effort cancellation. Setup script is idempotent, so a partial
    /// install can simply be retried.
    public func cancel() {
        cancelled = true
        setupProcess?.terminate()
        if isActive {
            phase = .cancelled
            appendLog("正在取消...")
        }
    }

    // MARK: - Archive

    /// Archive pinned to the app's own release tag, so the CLI version always
    /// matches the app version that ships this installer.
    public nonisolated static var releaseVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return v.isEmpty ? "0" : v
    }

    public nonisolated static func archiveURL(tag: String) -> URL {
        let safe = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        return URL(string: "https://github.com/GabrielMu2006/APIMeter/archive/refs/tags/v" + safe + ".zip")!
    }

    public nonisolated static var downloadURL: URL {
        archiveURL(tag: releaseVersion)
    }

    private func downloadArchive() async throws -> URL {
        let url = Self.downloadURL
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DeepSeekSyncSetupError.downloadFailed("HTTP " + String((response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        let expected = http.expectedContentLength > 0 ? Double(http.expectedContentLength) : nil
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("apimeter-ds-" + UUID().uuidString + ".zip")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmp)
        var buffer = Data()
        var received = 0.0
        var lastProgress = Date()
        do {
            for try await byte in bytes {
                buffer.append(byte)
                received += 1
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
                if let expected, Date().timeIntervalSince(lastProgress) > 0.15 {
                    phase = .downloading(min(1.0, received / expected))
                    lastProgress = Date()
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tmp)
            throw DeepSeekSyncSetupError.downloadFailed(error.localizedDescription)
        }
        phase = .downloading(1)
        return tmp
    }

    // MARK: - Extraction

    /// Extracts the archive into a scratch dir and finds the DeepSeekSync
    /// module directory inside (GitHub archives add a root folder first).
    private func extractModule(from zipURL: URL) async throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("apimeter-ds-extract-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dest) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, dest.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw DeepSeekSyncSetupError.extractionFailed(message)
        }
        try? FileManager.default.removeItem(at: zipURL)
        guard let module = Self.locateModule(under: dest) else {
            throw DeepSeekSyncSetupError.moduleNotFound
        }
        return module
    }

    /// Finds `.../<anything>/DeepSeekSync` with package.json + deepseek-sync
    /// + scripts/setup-runtime.sh (pure recursion, used by tests too).
    public nonisolated static func locateModule(under base: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "DeepSeekSync" else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let pkg = url.appendingPathComponent("package.json")
            let launcher = url.appendingPathComponent("deepseek-sync")
            let script = url.appendingPathComponent("scripts/setup-runtime.sh")
            if fm.fileExists(atPath: pkg.path),
               fm.fileExists(atPath: launcher.path),
               fm.fileExists(atPath: script.path) {
                candidates.append(url)
            }
        }
        return candidates.sorted { $0.path < $1.path }.first
    }

    /// Owned location for the managed copy: ~/Library/Application Support/APIMeter/DeepSeekSync.
    public nonisolated static func moduleDestination() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("APIMeter", isDirectory: true)
            .appendingPathComponent("DeepSeekSync", isDirectory: true)
    }

    private func prepareDestination(_ dest: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Never clobber a directory the user configured elsewhere; only a
        // leftover partial managed copy (not configured) may be replaced.
        if fm.fileExists(atPath: dest.path) {
            guard settings.syncToolPath != dest.path else { return }
            try fm.removeItem(at: dest)
        }
    }

    /// Downloaded ZIPs carry the quarantine attribute; drop it so the
    /// bundled scripts and binaries can run without a Gatekeeper prompt.
    private static func stripQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Runtime setup

    private func runSetupScript(in dir: URL) async throws {
        let script = dir.appendingPathComponent("scripts/setup-runtime.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        setupProcess = process
        try process.run()

        let handle = pipe.fileHandleForReading
        let reader = Task { @MainActor [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    self?.appendLog(line)
                }
            } catch {
                // Pipe closed - fine.
            }
        }
        while setupProcess?.isRunning == true {
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        _ = await reader.value
        let status = setupProcess?.terminationStatus ?? 1
        setupProcess = nil
        guard status == 0, !cancelled else {
            throw DeepSeekSyncSetupError.setupFailed(status)
        }
    }

    // MARK: - Login

    private func launchLogin(in dir: URL) throws {
        let cli = dir.appendingPathComponent("deepseek-sync")
        guard FileManager.default.fileExists(atPath: cli.path) else {
            throw DeepSeekSyncSetupError.launcherMissing(cli.path)
        }
        let process = Process()
        if FileManager.default.isExecutableFile(atPath: cli.path) {
            process.executableURL = cli
            process.arguments = ["login"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [cli.path, "login"]
        }
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        loginProcess = process
        try process.run()
        appendLog("已打开 DeepSeek 登录窗口，请在弹出的浏览器中完成登录。")
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.loginProcess?.isRunning == true {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            let status = self.loginProcess?.terminationStatus ?? 1
            self.loginProcess = nil
            if status == 0 {
                self.settings.lastSyncFailureDay = nil
                self.appendLog("登录成功，会话已保存到钥匙串。")
            } else {
                self.appendLog("登录窗口已关闭（未完成登录）。可稍后重试：设置 → 数据 → 重新打开登录。")
            }
        }
    }

    private func appendLog(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let combined = logTail.isEmpty ? trimmed : logTail + "\n" + trimmed
        logTail = String(combined.suffix(8000))
    }
}
