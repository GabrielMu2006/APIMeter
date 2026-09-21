import Foundation
import Testing
@testable import APIMeterCore

/// Fixture-driven tests for the Qoder quota decoder: personal monthly pool,
/// org resource package (present / unavailable), percentage derived from
/// used/total (the wire percentage has an ambiguous scale), epoch-ms reset.
struct QoderQuotaParsingTests {

    private func fixture(_ json: String) throws -> CodingPlanQuota {
        try QoderQuotaDecoder.decode(data: Data(json.utf8))
    }

    @Test func personalPoolOnly() throws {
        let quota = try fixture("""
        {
          "userType": "teams",
          "isQuotaExceeded": false,
          "expiresAt": 1790784000000,
          "userQuota": { "total": 2011.0, "used": 46.0, "remaining": 1965.0,
                         "percentage": 0.03, "unit": "credits" },
          "orgResourcePackage": { "used": 0, "remaining": 0, "percentage": 0,
                                  "unit": "credits", "cap": -1, "available": false }
        }
        """)
        #expect(quota.planLevel == "Teams")
        #expect(quota.windows.count == 1, "unavailable org pool must be omitted")

        let monthly = quota.monthly
        #expect(monthly?.usedValue == 46)
        #expect(monthly?.totalValue == 2011)
        #expect(monthly?.remaining == 1965)
        // Percentage derived from used/total (46/2011 ≈ 2.29%), not the
        // ambiguous wire percentage.
        #expect(monthly?.usedPercent != nil)
        let percent = Double(truncating: (monthly?.usedPercent ?? 0) as NSDecimalNumber)
        #expect(abs(percent - 2.287) < 0.01)
        #expect(monthly?.resetsAt == Date(timeIntervalSince1970: 1_790_784_000))
    }

    @Test func orgPoolIncludedWhenAvailable() throws {
        let quota = try fixture("""
        {
          "userType": "teams",
          "userQuota": { "total": 2011, "used": 46, "remaining": 1965 },
          "orgResourcePackage": { "total": 5000, "used": 2500, "remaining": 2500,
                                  "unit": "credits", "cap": 5000, "available": true }
        }
        """)
        #expect(quota.windows.count == 2)
        let org = quota.orgMonthly
        #expect(org?.usedPercent == 50)
        #expect(org?.remaining == 2500)
        #expect(quota.monthly != nil)
    }

    @Test func overLimitClampsToHundredPercent() throws {
        let quota = try fixture("""
        {
          "userQuota": { "total": 100, "used": 150 }
        }
        """)
        #expect(quota.monthly?.usedPercent == 100)
        #expect(quota.monthly?.effectiveRemaining == 0)
    }

    @Test func zeroTotalWithoutUsageIsSkipped() {
        #expect(throws: QoderError.self) {
            _ = try fixture("""
            { "userQuota": { "total": 0, "used": 0, "remaining": 0 } }
            """)
        }
    }

    @Test func remainingDerivedWhenAbsent() throws {
        let quota = try fixture("""
        { "userQuota": { "total": 800, "used": 300 } }
        """)
        #expect(quota.monthly?.remaining == 500)
        #expect(quota.monthly?.usedPercent == 37.5)
    }
}
