import Foundation
import Testing
@testable import APIMeterCore

/// Cursor usage RPC decoding: connect-rpc JSON with protobuf int64 encoded
/// as strings, optional planUsage fields, and the billing cycle mapped onto
/// the shared monthly window kind.
struct CursorQuotaParsingTests {

    static func fullFixture(totalPercent: Double = 42.5, endMs: Int = 1_795_174_903_380) -> String {
        """
        {
          "billingCycleStart": "1794570103380",
          "billingCycleEnd": "\(endMs)",
          "planUsage": {
            "remainingBonus": false,
            "bonusTooltip": "We work with model providers...",
            "autoPercentUsed": 0.28,
            "totalPercentUsed": \(totalPercent)
          },
          "spendLimitUsage": {"limitType": "user"},
          "displayThreshold": 200,
          "enabled": true,
          "displayMessage": "You've used 0% of your included usage"
        }
        """
    }

    @Test func decodesBillingCycleWindow() throws {
        let quota = try CursorQuotaDecoder.decode(data: Data(Self.fullFixture().utf8))
        #expect(quota.windows.count == 1)
        let window = try #require(quota.monthly)
        #expect(window.kind == .monthly)
        #expect(window.usedPercent == 42.5)
        let expected = Date(timeIntervalSince1970: 1_795_174_903.38)
        #expect(window.resetsAt.map { abs($0.timeIntervalSince(expected)) < 1 } == true)
    }

    @Test func acceptsNumericInt64AndFallsBackToAutoPercent() throws {
        let json = """
        {
          "billingCycleStart": 1794570103380,
          "billingCycleEnd": 1795174903380,
          "planUsage": {"autoPercentUsed": 7.25}
        }
        """
        let quota = try CursorQuotaDecoder.decode(data: Data(json.utf8))
        let window = try #require(quota.monthly)
        #expect(window.usedPercent == 7.25)
    }

    @Test func clampsOutOfScalePercentages() throws {
        let quota = try CursorQuotaDecoder.decode(data: Data(Self.fullFixture(totalPercent: 240).utf8))
        #expect(quota.monthly?.usedPercent == 100)
        let negative = try CursorQuotaDecoder.decode(data: Data(Self.fullFixture(totalPercent: -5).utf8))
        #expect(negative.monthly?.usedPercent == 0)
    }

    @Test func rejectsResponsesWithoutUsablePercent() {
        #expect(throws: CursorError.self) {
            try CursorQuotaDecoder.decode(data: Data("{\"enabled\":true}".utf8))
        }
        #expect(throws: CursorError.self) {
            try CursorQuotaDecoder.decode(data: Data("{\"planUsage\":{}}".utf8))
        }
        #expect(throws: CursorError.self) {
            try CursorQuotaDecoder.decode(data: Data("not json".utf8))
        }
    }
}
