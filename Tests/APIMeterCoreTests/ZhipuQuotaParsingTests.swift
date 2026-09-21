import Foundation
import Testing
@testable import APIMeterCore

/// Fixture-driven tests for the quota monitor response decoder. The schema
/// is cross-confirmed from the official glm-plan-usage plugin and community
/// implementations; every defensive branch below mirrors a quirk observed
/// in the wild (string numbers, ms/s/ISO reset stamps, body-level auth
/// codes on HTTP 200, unit/number window encoding).
struct ZhipuQuotaParsingTests {

    private func fixture(_ json: String) throws -> CodingPlanQuota {
        try ZhipuQuotaDecoder.decode(data: Data(json.utf8))
    }

    @Test func happyPathDecodesWindowsAndLevel() throws {
        let quota = try fixture("""
        {
          "success": true,
          "code": 200,
          "msg": "OK",
          "data": {
            "level": "pro",
            "limits": [
              { "type": "CREDIT_LIMIT", "usage": 120000, "currentValue": 36000,
                "percentage": 30, "remaining": 84000, "nextResetTime": 1789752000,
                "unit": 3, "number": 5,
                "usageDetails": [ { "modelCode": "GLM-5.3", "usage": 30000 },
                                  { "modelCode": "GLM-5.3-Flash", "usage": 6000 } ] },
              { "type": "TOKENS_LIMIT", "usage": 1000000, "currentValue": 750000,
                "percentage": 75, "remaining": 250000, "nextResetTime": 1789948800000,
                "unit": 6, "number": 1 },
              { "type": "TIME_LIMIT", "usage": 100, "currentValue": 42, "percentage": 42 }
            ]
          }
        }
        """)
        #expect(quota.planLevel == "pro")
        #expect(quota.windows.count == 3)

        let fiveHour = quota.fiveHour
        #expect(fiveHour?.usedPercent == 30)
        #expect(fiveHour?.usedValue == 36000)
        #expect(fiveHour?.totalValue == 120000)
        #expect(fiveHour?.remaining == 84000)
        #expect(fiveHour?.resetsAt == Date(timeIntervalSince1970: 1789752000))
        #expect(fiveHour?.modelDetails.count == 2)
        #expect(fiveHour?.modelDetails.first?.modelCode == "GLM-5.3")
        #expect(fiveHour?.health == .green)

        // Millisecond epochs divide down to seconds.
        #expect(quota.weekly?.usedPercent == 75)
        #expect(quota.weekly?.resetsAt == Date(timeIntervalSince1970: 1789948800))
        #expect(quota.weekly?.health == .orange)

        #expect(quota.monthlyTool?.usedPercent == 42)
    }

    @Test func stringNumbersAndIsoResetTimes() throws {
        let quota = try fixture("""
        {
          "success": true,
          "data": {
            "level": "lite",
            "limits": [
              { "type": "CREDIT_LIMIT", "usage": "200000", "currentValue": "190000",
                "percentage": "95", "remaining": "10000",
                "nextResetTime": "2026-09-19T12:00:00Z",
                "unit": "3", "number": "5" }
            ]
          }
        }
        """)
        let fiveHour = quota.fiveHour
        #expect(fiveHour?.usedPercent == 95)
        #expect(fiveHour?.usedValue == 190000)
        #expect(fiveHour?.totalValue == 200000)
        #expect(fiveHour?.resetsAt == ISO8601.date("2026-09-19T12:00:00Z"))
        #expect(fiveHour?.health == .red)
    }

    @Test func percentageFallsBackToCurrentOverUsage() throws {
        let quota = try fixture("""
        {
          "success": true,
          "data": { "limits": [
            { "type": "CREDIT_LIMIT", "usage": 400, "currentValue": 100,
              "unit": 3, "number": 5 }
          ] }
        }
        """)
        #expect(quota.fiveHour?.usedPercent == 25)
    }

    @Test func bodyLevelAuthCodeThrowsEvenOnSuccess() {
        #expect(throws: ZCodeError.authenticationFailed) {
            _ = try fixture("""
            { "success": false, "code": 401, "msg": "token expired or incorrect" }
            """)
        }
        #expect(throws: ZCodeError.authenticationFailed) {
            _ = try fixture("""
            { "success": false, "code": 403, "msg": "forbidden" }
            """)
        }
    }

    @Test func unknownWindowEncodingsAreIgnored() throws {
        let quota = try fixture("""
        {
          "success": true,
          "data": { "limits": [
            { "type": "CREDIT_LIMIT", "usage": 100, "currentValue": 50, "percentage": 50,
              "unit": 9, "number": 3 },
            { "type": "SOMETHING_NEW", "usage": 100, "currentValue": 50, "percentage": 50,
              "unit": 3, "number": 5 }
          ] }
        }
        """)
        // Unknown unit/number is skipped; unknown type with a known
        // unit/number pair still resolves to a window.
        #expect(quota.windows.count == 1)
        #expect(quota.fiveHour?.usedPercent == 50)
    }

    @Test func noUsableWindowsThrowsInvalidResponse() {
        #expect(throws: ZCodeError.self) {
            _ = try fixture("""
            { "success": true, "data": { "limits": [ { "type": "OTHER", "usage": 1 } ] } }
            """)
        }
    }

    @Test func emptyLimitsThrowsInvalidResponse() {
        #expect(throws: ZCodeError.self) {
            _ = try fixture("""
            { "success": true, "data": {} }
            """)
        }
    }

    @Test func windowKindFromUnitAndNumber() {
        #expect(ZhipuQuotaDecoder.kind(type: nil, unit: 3, number: 5) == .fiveHour)
        #expect(ZhipuQuotaDecoder.kind(type: nil, unit: 6, number: 1) == .weekly)
        #expect(ZhipuQuotaDecoder.kind(type: "TIME_LIMIT", unit: nil, number: nil) == .monthlyTool)
        #expect(ZhipuQuotaDecoder.kind(type: "CREDIT_LIMIT", unit: 1, number: 1) == nil)
    }

    @Test func healthThresholds() {
        #expect(QuotaHealth.of(usedPercent: 69) == .green)
        #expect(QuotaHealth.of(usedPercent: 70) == .orange)
        #expect(QuotaHealth.of(usedPercent: 90) == .red)
        #expect(QuotaHealth.of(usedPercent: nil) == .unknown)
    }

    @Test func remainingHelpers() throws {
        let quota = try fixture("""
        {
          "success": true,
          "data": { "limits": [
            { "type": "CREDIT_LIMIT", "usage": 2000, "currentValue": 1320,
              "percentage": 66, "remaining": 680, "unit": 3, "number": 5 },
            { "type": "CREDIT_LIMIT", "usage": 10000, "currentValue": 7093,
              "percentage": 70, "unit": 6, "number": 1 }
          ] }
        }
        """)
        // Server-reported remaining wins.
        #expect(quota.fiveHour?.remainingPercent == 34)
        #expect(quota.fiveHour?.effectiveRemaining == 680)
        // Falls back to total minus used when the field is absent.
        #expect(quota.weekly?.effectiveRemaining == 2907)
    }
}
