import Foundation

/// Decides which source's value a day shows when multiple sources exist.
/// Rule (spec 26/27): official CSV overrides local gateway estimates.
public enum UsageReconciler {

    /// Picks the winning daily value. Official rows win for a day.
    /// Returns nil when a day has no data at all.
    public static func reconcile(day: LocalDay, official: DailyValue?, estimated: DailyValue?) -> DailyUsage? {
        if let official {
            return DailyUsage(
                day: day,
                cost: official.cost,
                requests: official.requests,
                tokens: official.tokens,
                verification: .official,
                sources: official.sources.union(estimated?.sources ?? [])
            )
        }
        if let estimated {
            return DailyUsage(
                day: day,
                cost: estimated.cost,
                requests: estimated.requests,
                tokens: estimated.tokens,
                verification: .estimated,
                sources: estimated.sources
            )
        }
        return nil
    }

    public struct DailyValue: Equatable, Sendable {
        public let cost: Decimal?
        public let requests: Int64?
        public let tokens: Int64?
        public let sources: Set<UsageSource>
        public init(cost: Decimal?, requests: Int64?, tokens: Int64?, sources: Set<UsageSource>) {
            self.cost = cost
            self.requests = requests
            self.tokens = tokens
            self.sources = sources
        }
    }
}
