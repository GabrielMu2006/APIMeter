import Foundation

/// Runs the DeepSeekSync CLI exactly once per calendar day at 00:30
/// (or on the next check after that moment - launch/wake catch-up).
/// The manual Refresh button never touches this; it only checks the
/// schedule. On success the downloaded ZIP is imported automatically.
@MainActor
public final class SyncScheduler {
    public struct RunResult {
        public let ok: Bool
        public let message: String
        public let importedRecords: Int?
        public let fileHash: String?
    }

    private let environment: AppEnvironment
    private var checkTimer: Timer?
    private var isRunning = false
    public private(set) var lastResult: RunResult?
    public private(set) var lastAttemptAt: Date?

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func start() {
        scheduleChecks()
        // Catch-up: if today's run was missed (app closed at 00:30), run now.
        // force: a re-login after a failure recovers via app relaunch.
        Task { await checkAndRunIfDue(force: true) }
    }

    public var nextRunText: String {
        guard let next = SyncSchedule.nextRun() else { return "unknown" }
        return next.formatted(date: .abbreviated, time: .shortened)
    }

    private func scheduleChecks() {
        checkTimer?.invalidate()
        let timer = Timer(timeInterval: 10 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAndRunIfDue(force: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
    }

    private func checkAndRunIfDue(force: Bool) async {
        guard !isRunning else { return }
        guard SyncSchedule.shouldRun(
            lastSyncDay: environment.settings.lastSyncDay,
            lastFailureDay: environment.settings.lastSyncFailureDay,
            force: force
        ) else { return }
        await run()
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        lastAttemptAt = Date()

        // 1. Run the sync CLI (hidden browser, ~1 min) and parse its JSON.
        guard let output = await runSyncCLI() else {
            _ = markFailure()
            return
        }
        if output.sessionExpired {
            // Only the FIRST failure of the day notifies (spam fix: the
            // 10-min timer is also suppressed after this by the cooldown).
            let firstFailureToday = markFailure()
            finish(ok: false, message: "DeepSeek session expired. Please login again.")
            if firstFailureToday {
                postFailureNotification("DeepSeek session expired. Please login again.")
            }
            return
        }
        guard output.ok, let path = output.path, let hash = output.sha256 else {
            _ = markFailure()
            finish(ok: false, message: output.error ?? "sync failed")
            return
        }

        // 2. Auto-import the downloaded ZIP (dedup-safe; duplicates are fine).
        do {
            let result = try await environment.importService.importFile(
                at: URL(fileURLWithPath: path),
                mapper: DeepSeekOfficialCSVMapper()
            )
            environment.settings.lastSyncDay = LocalDay(date: Date()).value
            environment.settings.lastSyncFailureDay = nil
            finish(ok: true, message: "Imported " + String(result.inserted) + " new records", importedRecords: result.inserted, fileHash: hash)
            await environmentStateRefresh()
            Log.info("SyncScheduler: daily export synced and imported (" + String(result.inserted) + " new records)")
        } catch let error as ImportError {
            if Self.isBenignImportError(error) {
                // Already imported (same-day re-run or duplicate): success.
                environment.settings.lastSyncDay = LocalDay(date: Date()).value
                environment.settings.lastSyncFailureDay = nil
                finish(ok: true, message: error.localizedDescription, importedRecords: 0, fileHash: hash)
            } else {
                // Any other import failure keeps today marked as NOT synced
                // so it retries later (Codex review P0).
                _ = markFailure()
                finish(ok: false, message: "import failed: " + error.localizedDescription)
            }
        } catch {
            _ = markFailure()
            finish(ok: false, message: "import failed: " + error.localizedDescription)
        }
    }

    /// Cooldown: one failed attempt per day - the 10-minute timer must not
    /// spam terminal failures (or their notifications).
    /// - Returns: true when this is the FIRST failure of the day (caller may
    ///   notify); false for repeats.
    @discardableResult
    private func markFailure() -> Bool {
        let today = LocalDay(date: Date()).value
        let first = environment.settings.lastSyncFailureDay != today
        environment.settings.lastSyncFailureDay = today
        return first
    }

    /// Only a duplicate file is a benign "already done" outcome. Anything
    /// else (unsupported schema, empty file, ZIP failure, too large, ...)
    /// must stay a FAILURE so the day retries.
    static func isBenignImportError(_ error: ImportError) -> Bool {
        if case .duplicateFile = error { return true }
        return false
    }

    private func environmentStateRefresh() async {
        // Refresh dashboard data after an import (UI may or may not be visible).
        guard let state = AppState.current else { return }
        await state.dashboardViewModel.reload()
    }

    struct CLIOutput {
        let ok: Bool
        let sessionExpired: Bool
        let error: String?
        let path: String?
        let sha256: String?
    }

    /// Parses the single JSON line the CLI prints (stdout, both outcomes).
    static func parseCLIOutput(_ line: String) -> CLIOutput? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return CLIOutput(
            ok: obj["ok"] as? Bool ?? false,
            sessionExpired: obj["sessionExpired"] as? Bool ?? false,
            error: obj["error"] as? String,
            path: obj["path"] as? String,
            sha256: obj["sha256"] as? String
        )
    }

    private func runSyncCLI() async -> CLIOutput? {
        guard let toolDir = environment.settings.syncToolPath, !toolDir.isEmpty else {
            finish(ok: false, message: "DeepSeekSync not configured - set its path in Settings > Data")
            return nil
        }
        let cliPath = toolDir + "/deepseek-sync"
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            finish(ok: false, message: "DeepSeekSync not found at " + cliPath)
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["sync", "--json"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            finish(ok: false, message: "could not launch sync: " + error.localizedDescription)
            return nil
        }
        // The sync takes ~1 minute (browser + download). Await without
        // blocking the main thread (Task.sleep keeps the UI responsive).
        let deadline = Date().addingTimeInterval(300)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if process.isRunning {
            process.terminate()
            finish(ok: false, message: "sync timed out after 5 minutes")
            return nil
        }
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let lineSubstring = stdout.split(separator: "\n").last else {
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errLine = stderr.split(separator: "\n").last.map(String.init) ?? "unknown error"
            finish(ok: false, message: "sync failed: " + errLine)
            return nil
        }
        let line = String(lineSubstring)
        guard let output = Self.parseCLIOutput(line) else {
            finish(ok: false, message: "unparseable sync output")
            return nil
        }
        return output
    }

    private func finish(ok: Bool, message: String, importedRecords: Int? = nil, fileHash: String? = nil) {
        lastResult = RunResult(ok: ok, message: message, importedRecords: importedRecords, fileHash: fileHash)
        environment.settings.lastSyncResult = (ok ? "OK" : "FAILED") + " " + message
        Log.info("SyncScheduler: " + (ok ? "OK" : "FAILED") + " " + message)
    }

    private func postFailureNotification(_ message: String) {
        Task { @MainActor in
            await environment.alertService.postNotification(title: "API Meter Sync", body: message)
        }
    }
}
