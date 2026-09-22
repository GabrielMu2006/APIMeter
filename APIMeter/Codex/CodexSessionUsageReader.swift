import Foundation

/// Offline fallback for the Codex quota: the Codex CLI appends a fresh
/// rate_limits snapshot (the same data the usage endpoint serves) to the
/// session rollout file after every model call. When chatgpt.com is not
/// reachable from API Meter's context, the newest snapshot on disk is a
/// close-to-real-time proxy - it only lags by the time since the user last
/// ran Codex.
///
/// File layout: <CODEX_HOME>/sessions/YYYY/MM/DD/rollout-*.jsonl, one JSON
/// object per line; the interesting shape is
///   {"type":"event_msg", ..., "payload": { "rate_limits": {
///     "primary":   { "used_percent": 6.0, "window_minutes": 300, "resets_at": 1790020420 },
///     "secondary": { "used_percent": 14.0, "window_minutes": 10080, "resets_at": ... },
///     "plan_type": "plus", ... }}}
public struct CodexSessionUsageReader: Sendable {
    private let sessionsDirectory: URL

    /// - Parameter sessionsDirectory: the sessions root. Injectable for
    ///   tests; defaults to `<CODEX_HOME or ~/.codex>/sessions`.
    public init(homeDirectory: URL? = nil) {
        let home: URL
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            home = URL(fileURLWithPath: override)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
        self.init(sessionsDirectory: home.appendingPathComponent("sessions", isDirectory: true))
    }

    public init(sessionsDirectory: URL) {
        self.sessionsDirectory = sessionsDirectory
    }

    /// Newest rate_limits snapshot found on disk, or nil when there is no
    /// session data at all.
    public func latestQuota(
        now: Date = Date(),
        maxFiles: Int = 4,
        tailBytes: Int = 512 * 1024
    ) -> CodingPlanQuota? {
        let files = Self.rolloutFiles(under: sessionsDirectory, maxFiles: maxFiles)
        for file in files {
            if let quota = latestQuota(in: file, tailBytes: tailBytes) {
                return quota
            }
        }
        return nil
    }

    func latestQuota(in file: URL, tailBytes: Int) -> CodingPlanQuota? {
        guard let data = Self.tail(of: file, bytes: tailBytes) else { return nil }
        // The first segment may be a partial line - skip it.
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        for line in lines.dropFirst().reversed() {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let rateLimits = payload["rate_limits"] as? [String: Any],
                  let quota = Self.quota(from: rateLimits, fetchedAt: Self.modificationDate(of: file))
            else { continue }
            return quota
        }
        return nil
    }

    // MARK: - Internals (exposed for tests)

    static func rolloutFiles(under directory: URL, maxFiles: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-") else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }
        return files
            .sorted { $0.date > $1.date }
            .prefix(maxFiles)
            .map { $0.url }
    }

    static func tail(of file: URL, bytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file),
              let size = try? handle.seekToEnd(), size > 0
        else { return nil }
        let readOffset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: readOffset)
        let data = try? handle.read(upToCount: Int(size - readOffset))
        try? handle.close()
        return data
    }

    static func modificationDate(of file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }

    /// Window length in minutes -> the two windows the plan meters.
    static func kind(windowMinutes: Int?) -> QuotaWindowKind? {
        guard let minutes = windowMinutes else { return nil }
        if (290...310).contains(minutes) { return .fiveHour }
        if (10_000...10_200).contains(minutes) { return .weekly }
        return nil
    }

    static func quota(from rateLimits: [String: Any], fetchedAt: Date) -> CodingPlanQuota? {
        var windows: [QuotaWindow] = []
        for key in ["primary", "secondary"] {
            guard let window = rateLimits[key] as? [String: Any],
                  let kind = kind(windowMinutes: number(window["window_minutes"])?.intValue),
                  let percentNumber = number(window["used_percent"])
            else { continue }
            let percent = percentNumber.decimalValue
            windows.append(QuotaWindow(
                kind: kind,
                usedPercent: Swift.min(100, Swift.max(0, percent)),
                usedValue: nil,
                totalValue: nil,
                remaining: nil,
                resetsAt: number(window["resets_at"]).map {
                    $0.doubleValue > 1_000_000_000_000
                        ? Date(timeIntervalSince1970: $0.doubleValue / 1000)
                        : Date(timeIntervalSince1970: $0.doubleValue)
                },
                modelDetails: []
            ))
        }
        guard !windows.isEmpty else { return nil }
        return CodingPlanQuota(
            planLevel: (rateLimits["plan_type"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            windows: windows,
            fetchedAt: fetchedAt
        )
    }

    /// JSONSerialization numbers arrive as NSNumber; strings tolerated.
    static func number(_ value: Any?) -> NSDecimalNumber? {
        switch value {
        case let number as NSNumber:
            return NSDecimalNumber(decimal: Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")) ?? 0)
        case let string as String:
            return Decimal(string: string.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX")).map(NSDecimalNumber.init)
        default:
            return nil
        }
    }
}
