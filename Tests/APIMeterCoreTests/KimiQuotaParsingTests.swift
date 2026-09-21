import Foundation
import Testing
@testable import APIMeterCore

/// Fixture-driven tests for the Kimi usage decoder, mirroring the quirks
/// observed in the wild: number/string duality, ISO or epoch reset stamps,
/// the top-level `usage` envelope being the WEEKLY quota, the 5-hour window
/// arriving via limits[] with TIME_UNIT_MINUTE x 300, and missing `used`
/// derived from limit - remaining.
struct KimiQuotaParsingTests {

    private func fixture(_ json: String) throws -> CodingPlanQuota {
        try KimiQuotaDecoder.decode(data: Data(json.utf8))
    }

    @Test func happyPathWeeklyFromUsageAndFiveHourFromLimits() throws {
        let quota = try fixture("""
        {
          "usage": { "limit": 1000, "remaining": 400, "used": 600,
                     "resetTime": 1789948800 },
          "limits": [
            { "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
              "detail": { "limit": 200, "remaining": 150, "used": 50,
                          "resetTime": "2026-09-19T17:56:17Z" } },
            { "window": { "duration": 1, "timeUnit": "TIME_UNIT_HOUR" },
              "detail": { "limit": 50, "remaining": 50 } }
          ],
          "user": { "membership": { "level": "LEVEL_INTERMEDIATE" } },
          "parallel": { "limit": 3 }
        }
        """)
        #expect(quota.planLevel == "Intermediate")
        #expect(quota.windows.count == 2)

        let weekly = quota.weekly
        #expect(weekly?.usedPercent == 60)
        #expect(weekly?.usedValue == 600)
        #expect(weekly?.totalValue == 1000)
        #expect(weekly?.remaining == 400)
        #expect(weekly?.resetsAt == Date(timeIntervalSince1970: 1789948800))

        let fiveHour = quota.fiveHour
        #expect(fiveHour?.usedPercent == 25)
        #expect(fiveHour?.remaining == 150)
        #expect(fiveHour?.resetsAt == ISO8601.date("2026-09-19T17:56:17Z"))
        // The short hourly rate-limit window is ignored for display.
        #expect(quota.windows.contains(where: { $0.kind == .fiveHour }))
        #expect(quota.windows.count { $0.kind == .weekly } == 1)
    }

    @Test func officialRatiosWinOverIntegerMath() throws {
        // The `usages` object (limit_5h/limit_7d, used_ratio 0-1 floats) is
        // the authoritative fine-grained source - it overrides the coarse
        // envelope integers and supplies its own reset stamps.
        let quota = try fixture("""
        {
          "usage": { "limit": "100", "remaining": "100",
                     "resetTime": "2026-09-25T02:23:16.053628Z" },
          "limits": [
            { "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
              "detail": { "limit": "100", "remaining": "100",
                          "resetTime": "2026-09-19T18:23:16.053628Z" } }
          ],
          "usages": {
            "limit_5h": { "used_ratio": 0.25, "reset_time": "2026-09-19T18:23:16Z" },
            "limit_7d": { "used_ratio": 0.5, "reset_time": "2026-09-25T02:23:16Z" }
          }
        }
        """)
        #expect(quota.fiveHour?.usedPercent == 25)
        #expect(quota.weekly?.usedPercent == 50)
        // Integers from the envelope still feed the absolute context.
        #expect(quota.fiveHour?.totalValue == 100)
        #expect(quota.weekly?.totalValue == 100)
        // Ratio reset stamps win.
        #expect(quota.fiveHour?.resetsAt == ISO8601.date("2026-09-19T18:23:16Z"))
        #expect(quota.weekly?.resetsAt == ISO8601.date("2026-09-25T02:23:16Z"))
    }

    @Test func ratioOnlyResponseStillDecodes() throws {
        let quota = try fixture("""
        {
          "usages": {
            "limit_5h": { "used_ratio": "0.1", "reset_time": "2026-09-19T18:23:16Z" },
            "limit_7d": { "used_ratio": 0.2 }
          }
        }
        """)
        #expect(quota.fiveHour?.usedPercent == 10)
        #expect(quota.weekly?.usedPercent == 20)
        #expect(quota.fiveHour?.resetsAt == ISO8601.date("2026-09-19T18:23:16Z"))
        // No envelope integers -> no absolutes, percentages still render.
        #expect(quota.weekly?.totalValue == nil)
        #expect(quota.weekly?.effectiveRemaining == nil)
    }

    @Test func stringNumbersAndDerivedUsed() throws {
        let quota = try fixture("""
        {
          "usage": { "limit": "500", "remaining": "200",
                     "resetTime": "2026-09-26T00:00:00Z" },
          "limits": []
        }
        """)
        // used absent -> limit - remaining.
        #expect(quota.weekly?.usedValue == 300)
        #expect(quota.weekly?.usedPercent == 60)
        #expect(quota.weekly?.totalValue == 500)
    }

    @Test func fiveHourAlsoSpelledAsHours() throws {
        let quota = try fixture("""
        {
          "usage": { "limit": 100, "remaining": 90 },
          "limits": [
            { "window": { "duration": 5, "timeUnit": "hour" },
              "detail": { "limit": 10, "remaining": 4 } }
          ]
        }
        """)
        #expect(quota.fiveHour?.usedPercent == 60)
    }

    @Test func noUsableWindowsThrows() {
        #expect(throws: KimiError.self) {
            _ = try fixture("""
            { "limits": [], "user": {} }
            """)
        }
    }

    @Test func levelNormalization() {
        #expect(KimiQuotaDecoder.normalizeLevel("LEVEL_INTERMEDIATE") == "Intermediate")
        #expect(KimiQuotaDecoder.normalizeLevel("LEVEL_PLUS") == "Plus")
        #expect(KimiQuotaDecoder.normalizeLevel("pro") == "Pro")
    }
}

/// Direct value construction for isFiveHour (the JSON path is covered by
/// the fixtures above).
struct KimiWindowSpecDirectTests {
    private func spec(_ duration: Double?, _ unit: String?) -> KimiUsageResponse.KimiWindowSpec? {
        duration.map { KimiUsageResponse.KimiWindowSpec(duration: FlexibleDecimal(Decimal($0)), timeUnit: unit) }
    }

    @Test func detection() {
        #expect(KimiQuotaDecoder.isFiveHour(spec(300, "TIME_UNIT_MINUTE")))
        #expect(KimiQuotaDecoder.isFiveHour(spec(5, "hour")))
        #expect(KimiQuotaDecoder.isFiveHour(spec(300, "minute")))
        #expect(KimiQuotaDecoder.isFiveHour(spec(60, "TIME_UNIT_MINUTE")) == false)
        #expect(KimiQuotaDecoder.isFiveHour(spec(5, "TIME_UNIT_DAY")) == false)
        #expect(KimiQuotaDecoder.isFiveHour(nil) == false)
        #expect(KimiQuotaDecoder.isFiveHour(spec(nil, "hour")) == false)
    }
}
