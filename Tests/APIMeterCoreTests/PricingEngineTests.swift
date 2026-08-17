import Foundation
import Testing
import Foundation
import APIMeterCore

struct PricingEngineTests {

    private func date(_ iso: String) throws -> Date {
        try Date(iso, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false))
    }

    @Test func selectsRuleByTimestamp() throws {
        let v1 = PriceRule(model: "deepseek-chat", effectiveFrom: try date("2026-01-01T00:00:00Z"), cacheHitPrice: Decimal(1), cacheMissPrice: Decimal(2), outputPrice: Decimal(3), currency: "CNY")
        let v2 = PriceRule(model: "deepseek-chat", effectiveFrom: try date("2026-08-17T00:00:00Z"), cacheHitPrice: Decimal(2), cacheMissPrice: Decimal(4), outputPrice: Decimal(6), currency: "CNY")
        let before = try date("2026-06-01T00:00:00Z")
        let after = try date("2026-09-01T00:00:00Z")
        #expect(PricingEngine.selectRule(model: "deepseek-chat", at: before, rules: [v1, v2])?.cacheHitPrice == Decimal(1))
        #expect(PricingEngine.selectRule(model: "deepseek-chat", at: after, rules: [v1, v2])?.cacheHitPrice == Decimal(2))
    }

    @Test func ruleWithEndDateStopsApplying() throws {
        let v1 = PriceRule(model: "m", effectiveFrom: try date("2026-01-01T00:00:00Z"), effectiveTo: try date("2026-06-01T00:00:00Z"), cacheHitPrice: Decimal(1), cacheMissPrice: Decimal(1), outputPrice: Decimal(1), currency: "CNY")
        let at = try date("2026-07-01T00:00:00Z")
        #expect(PricingEngine.selectRule(model: "m", at: at, rules: [v1]) == nil)
    }

    @Test func costMathPerMillionTokens() {
        let rule = PriceRule(model: "m", effectiveFrom: Date(), cacheHitPrice: Decimal(0.5), cacheMissPrice: Decimal(2), outputPrice: Decimal(8), currency: "CNY")
        let cost = PricingEngine.cost(cacheHitTokens: 1_000_000, cacheMissTokens: 1_000_000, outputTokens: 500_000, rule: rule)
        // 0.5 + 2 + 4 = 6.5
        #expect(cost == Decimal(string: "6.5"))
    }

    @Test func noPricesMeansNoCost() {
        let rule = PriceRule(model: "m", effectiveFrom: Date(), currency: "CNY")
        let cost = PricingEngine.cost(cacheHitTokens: 100, cacheMissTokens: 100, outputTokens: 100, rule: rule)
        #expect(cost == nil)
    }
}
