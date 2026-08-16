import Foundation

/// Pure aggregation over [UsageRecord] into daily buckets.
/// One rule matters above all (spec 26): when a day has official CSV rows,
/// they override gateway estimates for that day - never summed.
public enum UsageAggregator {

    private struct Accumulator {
        var cost: Decimal?
        var requests: Int64?
        var tokens: Int64?
        var costProvided = false
        var requestsProvided = false
        var tokensProvided = false

        // A metric is the sum of whatever records provide it; nil only when NO
        // record provides it. Official exports split money (cost file) from
        // quantities (amount file) into separate records, so per-record
        // "missing" metrics are the rule, not the exception.
        mutating func add(_ record: UsageRecord) {
            if let amount = record.amount {
                cost = (cost ?? 0) + amount
                costProvided = true
            }
            if let count = record.requestCount {
                requests = (requests ?? 0) + count
                requestsProvided = true
            }
            if let tokenCount = record.totalTokens {
                tokens = (tokens ?? 0) + tokenCount
                tokensProvided = true
            }
        }

        var daily: (cost: Decimal?, requests: Int64?, tokens: Int64?) {
            (costProvided ? cost : nil, requestsProvided ? requests : nil, tokensProvided ? tokens : nil)
        }
    }

    /// Groups records by local day, applying the official-over-estimated rule.
    public static func daily(from records: [UsageRecord]) -> [DailyUsage] {
        var byDay: [LocalDay: [UsageSource: Accumulator]] = [:]
        for record in records {
            byDay[record.day, default: [:]][record.source, default: Accumulator()].add(record)
        }
        return byDay.keys.sorted().map { day in
            let perSource = byDay[day]!
            let sources = Set(perSource.keys)
            if let official = perSource[.officialCSV] {
                let d = official.daily
                return DailyUsage(day: day, cost: d.cost, requests: d.requests, tokens: d.tokens, verification: .official, sources: sources)
            }
            let estimated = perSource[.localGateway] ?? perSource[.balanceSnapshot] ?? Accumulator()
            let d = estimated.daily
            return DailyUsage(day: day, cost: d.cost, requests: d.requests, tokens: d.tokens, verification: .estimated, sources: sources)
        }
    }

    /// Full period summary (spec 79), including per-key breakdown.
    public static func summarize(_ records: [UsageRecord]) -> UsageSummary {
        let daily = daily(from: records)
        let cost = daily.compactMap { $0.cost }.reduce(Decimal.zero, +)
        let hasAnyCost = daily.contains { $0.cost != nil }
        let requests = daily.compactMap { $0.requests }.reduce(Int64.zero, +)
        let hasAnyRequests = daily.contains { $0.requests != nil }
        let tokens = daily.compactMap { $0.tokens }.reduce(Int64.zero, +)
        let hasAnyTokens = daily.contains { $0.tokens != nil }

        var byKey: [String: Accumulator] = [:]
        for record in records {
            let fp = record.apiKeyFingerprint ?? "(unknown)"
            byKey[fp, default: Accumulator()].add(record)
        }
        let byAPIKey = byKey.keys.sorted().map { fp -> APIKeyUsage in
            let d = byKey[fp]!.daily
            return APIKeyUsage(fingerprint: fp, displayName: nil, officialName: nil, cost: d.cost, requests: d.requests, tokens: d.tokens)
        }

        return UsageSummary(
            cost: hasAnyCost ? cost : nil,
            requests: hasAnyRequests ? requests : nil,
            tokens: hasAnyTokens ? tokens : nil,
            completeAmountData: daily.allSatisfy { $0.cost != nil },
            daily: daily,
            byAPIKey: byAPIKey
        )
    }
}
