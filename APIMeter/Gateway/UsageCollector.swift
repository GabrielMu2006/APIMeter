import Foundation

/// Records gateway-observed usage into SQLite.
/// Only metadata: fingerprint, model, tokens, request count, estimated cost.
/// Prompts and completions are NEVER captured (spec 21).
public struct UsageCollector: Sendable {
    private let repository: UsageRepository

    public init(repository: UsageRepository) {
        self.repository = repository
    }

    public func record(apiKey: String?, model: String?, usage: GatewayUsage?, at timestamp: Date) async {
        let fingerprint = apiKey.map(KeyFingerprint.sha256Hex)
        var record = UsageRecord(
            timestamp: timestamp,
            day: LocalDay(date: timestamp),
            apiKeyFingerprint: fingerprint,
            model: model,
            requestCount: 1,
            cacheHitTokens: usage?.cacheHitTokens,
            cacheMissTokens: usage?.cacheMissTokens,
            inputTokens: usage?.promptTokens,
            outputTokens: usage?.completionTokens,
            totalTokens: usage?.totalTokens,
            amount: nil,
            currency: nil,
            source: .localGateway,
            verification: .estimated
        )

        // Estimated cost via versioned pricing rules, only when rules exist.
        // Without a matching rule the amount stays nil (honest unknown, spec 119).
        if let model, let usage,
           let rules = try? repository.fetchPriceRules(provider: "deepseek"),
           let rule = PricingEngine.selectRule(model: model, at: timestamp, rules: rules) {
            let hit = usage.cacheHitTokens ?? 0
            let miss = usage.cacheMissTokens ?? 0
            let output = usage.completionTokens ?? 0
            if let cost = PricingEngine.cost(cacheHitTokens: hit, cacheMissTokens: miss, outputTokens: output, rule: rule) {
                record.amount = cost
                record.currency = rule.currency
            }
        }

        do {
            let stats = try repository.upsert([record])
            Log.info("Gateway usage recorded: model=" + (model ?? "unknown") + " inserted=" + String(stats.inserted))
        } catch {
            Log.error("Gateway usage record failed: " + Log.sanitize(error.localizedDescription))
        }
    }
}
