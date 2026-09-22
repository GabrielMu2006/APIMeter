import Foundation
import Testing
@testable import APIMeterCore

/// Fixture-driven tests for the Codex usage decoder: the two known windows
/// map onto fiveHour/weekly, unknown window lengths are skipped, percents
/// clamp, reset stamps arrive as epoch seconds.
struct CodexQuotaParsingTests {

    private func fixture(_ json: String, planFallback: String? = nil) throws -> CodingPlanQuota {
        try CodexQuotaDecoder.decode(data: Data(json.utf8), planTypeFallback: planFallback)
    }

    @Test func primaryAndSecondaryWindows() throws {
        let quota = try fixture("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window":   { "used_percent": 6, "limit_window_seconds": 18000,
                                  "reset_at": 1790020420 },
            "secondary_window": { "used_percent": 14.5, "limit_window_seconds": 604800,
                                  "reset_at": 1790519184 }
          }
        }
        """)
        #expect(quota.planLevel == "plus")
        #expect(quota.windows.count == 2)
        #expect(quota.fiveHour?.usedPercent == 6)
        #expect(quota.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_790_020_420))
        #expect(quota.weekly?.usedPercent == 14.5)
        #expect(quota.weekly?.resetsAt == Date(timeIntervalSince1970: 1_790_519_184))
    }

    @Test func stringNumbersAndPlanFallback() throws {
        let quota = try fixture("""
        {
          "rate_limit": {
            "primary_window": { "used_percent": "12", "limit_window_seconds": "18000" }
          }
        }
        """, planFallback: "pro")
        #expect(quota.planLevel == "pro")
        #expect(quota.fiveHour?.usedPercent == 12)
        #expect(quota.windows.count == 1, "secondary absent -> only one window")
    }

    @Test func unknownWindowLengthSkipped() {
        #expect(throws: CodexError.self) {
            _ = try fixture("""
            {
              "rate_limit": { "primary_window": { "used_percent": 5, "limit_window_seconds": 3600 } }
            }
            """)
        }
    }

    @Test func overLimitClamps() throws {
        let quota = try fixture("""
        {
          "rate_limit": { "primary_window": { "used_percent": 120, "limit_window_seconds": 18000 } }
        }
        """)
        #expect(quota.fiveHour?.usedPercent == 100)
    }

    @Test func windowKindDetection() {
        #expect(CodexQuotaDecoder.kind(windowSeconds: 18000) == .fiveHour)
        #expect(CodexQuotaDecoder.kind(windowSeconds: 604800) == .weekly)
        #expect(CodexQuotaDecoder.kind(windowSeconds: 3600) == nil)
        #expect(CodexQuotaDecoder.kind(windowSeconds: nil) == nil)
    }
}
