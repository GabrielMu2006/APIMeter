import Foundation

/// Versioned pricing (spec 28-30): rules live in SQLite, match requests by
/// model + timestamp, never hardcoded in business code.
public enum PricingEngine {

    /// Selects the rule effective at date for model (latest effective_from wins).
    public static func selectRule(model: String, at date: Date, rules: [PriceRule]) -> PriceRule? {
        rules
            .filter { $0.model == model && $0.effectiveFrom <= date && ($0.effectiveTo == nil || $0.effectiveTo! > date) }
            .max { $0.effectiveFrom < $1.effectiveFrom }
    }

    /// Cost = (cacheHit/1M * cacheHitPrice) + (cacheMiss/1M * cacheMissPrice) + (output/1M * outputPrice).
    /// Returns nil when the rule has no prices (honest unknown, never guessed).
    public static func cost(cacheHitTokens: Int64, cacheMissTokens: Int64, outputTokens: Int64, rule: PriceRule) -> Decimal? {
        guard let hitPrice = rule.cacheHitPrice, let missPrice = rule.cacheMissPrice, let outputPrice = rule.outputPrice else {
            return nil
        }
        let perMillion = Decimal(1_000_000)
        func part(_ tokens: Int64, _ price: Decimal) -> Decimal {
            (Decimal(tokens) / perMillion) * price
        }
        return part(cacheHitTokens, hitPrice) + part(cacheMissTokens, missPrice) + part(outputTokens, outputPrice)
    }
}
