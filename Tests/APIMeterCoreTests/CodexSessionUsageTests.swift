import Foundation
import Testing
@testable import APIMeterCore

/// Codex session-log offline fallback: newest rollout file wins, the
/// rate_limits envelope maps onto the shared quota windows, and huge files
/// are read from the tail.
struct CodexSessionUsageTests {

    /// Writes one rollout file with the given JSONL lines and mtime.
    static func makeSession(dir: URL, day: String, name: String, lines: [String], mtime: Date) throws -> URL {
        let dayDir = dir.appendingPathComponent(day, isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        let url = dayDir.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        return url
    }

    static func rateLimitsLine(primary: Double, secondary: Double, plan: String) -> String {
        """
        {"type":"event_msg","timestamp":"2026-09-21T15:31:18.646Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":\(primary),"window_minutes":300,"resets_at":1790020420},"secondary":{"used_percent":\(secondary),"window_minutes":10080,"resets_at":1790519184},"plan_type":"\(plan)"}}}
        """
    }

    @Test func newestFileWinsAndWindowsMap() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-sessions-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let oldDate = Date(timeIntervalSince1970: 1_789_000_000)
        let newDate = Date(timeIntervalSince1970: 1_789_090_000)
        _ = try Self.makeSession(
            dir: root, day: "2026-09-20",
            name: "rollout-old.jsonl",
            lines: [Self.rateLimitsLine(primary: 99, secondary: 99, plan: "plus")],
            mtime: oldDate
        )
        _ = try Self.makeSession(
            dir: root, day: "2026-09-21",
            name: "rollout-new.jsonl",
            lines: [
                #"{"type":"session_meta","payload":{"id":"x"}}"#,
                Self.rateLimitsLine(primary: 6, secondary: 14, plan: "plus"),
                #"{"type":"event_msg","payload":{"other":1}}"#,
            ],
            mtime: newDate
        )

        let reader = CodexSessionUsageReader(sessionsDirectory: root)
        let quota = try #require(reader.latestQuota())
        #expect(quota.planLevel == "plus")
        #expect(quota.fiveHour?.usedPercent == 6)
        #expect(quota.weekly?.usedPercent == 14)
        #expect(quota.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_790_020_420))
        #expect(quota.fetchedAt == newDate)
    }

    @Test func lastOccurrenceInOneFileWins() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-sessions-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try Self.makeSession(
            dir: root, day: "2026-09-21",
            name: "rollout-only.jsonl",
            lines: [
                Self.rateLimitsLine(primary: 10, secondary: 10, plan: "plus"),
                Self.rateLimitsLine(primary: 30, secondary: 17, plan: "plus"),
            ],
            mtime: Date()
        )

        let quota = try #require(CodexSessionUsageReader(sessionsDirectory: root).latestQuota())
        #expect(quota.fiveHour?.usedPercent == 30, "the most recent event inside a file wins")
    }

    @Test func tailReadHandlesLargeFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-sessions-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 600 KB of filler before the rate limits line - beyond the reader's
        // 512 KB tail, so only a partial-line-tolerant tail read finds it.
        let filler = #"{"type":"noise","payload":{"pad":""# + String(repeating: "x", count: 600_000) + #""}}"#
        _ = try Self.makeSession(
            dir: root, day: "2026-09-21",
            name: "rollout-big.jsonl",
            lines: [filler, Self.rateLimitsLine(primary: 42, secondary: 7, plan: "pro")],
            mtime: Date()
        )

        let reader = CodexSessionUsageReader(sessionsDirectory: root)
        let quota = try #require(reader.latestQuota(tailBytes: 512 * 1024))
        #expect(quota.fiveHour?.usedPercent == 42)
        #expect(quota.planLevel == "pro")
    }

    @Test func noSessionsReturnsNil() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-sessions-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(CodexSessionUsageReader(sessionsDirectory: root).latestQuota() == nil)
    }

    @Test func windowMinuteMapping() {
        #expect(CodexSessionUsageReader.kind(windowMinutes: 300) == .fiveHour)
        #expect(CodexSessionUsageReader.kind(windowMinutes: 10080) == .weekly)
        #expect(CodexSessionUsageReader.kind(windowMinutes: 60) == nil)
        #expect(CodexSessionUsageReader.kind(windowMinutes: nil) == nil)
    }
}
