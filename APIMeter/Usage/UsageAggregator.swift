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

    /// Per-day per-key costs from keyed records that carry an amount,
    /// sorted by cost descending. Billing rows (nil fingerprint) are excluded.
    /// Powers the chart hover tooltip (web-style per-key breakdown).
    public static func perKeyDailyCosts(_ records: [UsageRecord]) -> [LocalDay: [(fingerprint: String, cost: Decimal)]] {
        var byDay: [LocalDay: [String: Decimal]] = [:]
        for record in records {
            guard let fingerprint = record.apiKeyFingerprint, let amount = record.amount else { continue }
            byDay[record.day, default: [:]][fingerprint, default: 0] += amount
        }
        var result: [LocalDay: [(fingerprint: String, cost: Decimal)]] = [:]
        for (day, dict) in byDay {
            result[day] = dict
                .map { (fingerprint: $0.key, cost: $0.value) }
                .sorted { $0.cost > $1.cost }
        }
        return result
    }

    /// Sums two optional metrics; nil only when both are nil.
    private static func combine(_ a: Int64?, _ b: Int64?) -> Int64? {
        switch (a, b) {
        case (let x?, let y?): return x + y
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (nil, nil): return nil
        }
    }

    /// Bucket roles for one day. Official exports split billing rows
    /// (cost file: money, no key) from keyed rows (amount file: quantities +
    /// derived per-key cost). Billing money is authoritative for the day total;
    /// keyed derived money feeds only the per-key breakdown.
    private enum Bucket: Hashable {
        case officialBilling
        case officialKeyed
        case localGateway
        case balanceSnapshot
    }

    /// Groups records by local day, applying the official-over-estimated rule.
    public static func daily(from records: [UsageRecord]) -> [DailyUsage] {
        var byDay: [LocalDay: [Bucket: Accumulator]] = [:]
        for record in records {
            let bucket: Bucket
            switch record.source {
            case .officialCSV:
                bucket = record.apiKeyFingerprint == nil ? .officialBilling : .officialKeyed
            case .localGateway:
                bucket = .localGateway
            case .balanceSnapshot:
                bucket = .balanceSnapshot
            }
            byDay[record.day, default: [:]][bucket, default: Accumulator()].add(record)
        }
        return byDay.keys.sorted().map { day in
            let buckets = byDay[day]!
            let sources = Set(buckets.keys.map { bucket -> UsageSource in
                switch bucket {
                case .officialBilling, .officialKeyed: return .officialCSV
                case .localGateway: return .localGateway
                case .balanceSnapshot: return .balanceSnapshot
                }
            })
            if let billing = buckets[.officialBilling], billing.cost != nil || !buckets.keys.contains(.officialKeyed) {
                // Billing rows exist: their money is the day total. Quantities
                // come from both buckets (keyed rows in practice).
                let keyed = buckets[.officialKeyed] ?? Accumulator()
                let d = billing.daily
                let q = keyed.daily
                return DailyUsage(
                    day: day,
                    cost: d.cost,
                    requests: Self.combine(d.requests, q.requests),
                    tokens: Self.combine(d.tokens, q.tokens),
                    verification: .official,
                    sources: sources
                )
            }
            if let keyed = buckets[.officialKeyed] {
                // Amount-file-only days: derived per-key cost sums to the day total.
                let d = keyed.daily
                return DailyUsage(day: day, cost: d.cost, requests: d.requests, tokens: d.tokens, verification: .official, sources: sources)
            }
            let estimated = buckets[.localGateway] ?? buckets[.balanceSnapshot] ?? Accumulator()
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

        // Per-key breakdown: keyed rows only. Billing rows (nil fingerprint)
        // carry account-level totals and would double-count if included.
        var byKey: [String: Accumulator] = [:]
        for record in records {
            guard let fp = record.apiKeyFingerprint else { continue }
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
