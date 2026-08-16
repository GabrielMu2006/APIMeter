import Foundation

/// Aggregated usage for one local day.
public struct DailyUsage: Identifiable, Equatable, Sendable {
    public var id: LocalDay { day }
    public let day: LocalDay
    /// Nil when the sources provide no amounts for this day (UI shows "—").
    public let cost: Decimal?
    public let requests: Int64?
    public let tokens: Int64?
    public let verification: VerificationState
    public let sources: Set<UsageSource>

    public init(day: LocalDay, cost: Decimal?, requests: Int64?, tokens: Int64?, verification: VerificationState, sources: Set<UsageSource>) {
        self.day = day
        self.cost = cost
        self.requests = requests
        self.tokens = tokens
        self.verification = verification
        self.sources = sources
    }
}

/// Aggregated usage for one API key over a period.
public struct APIKeyUsage: Identifiable, Equatable, Sendable {
    public var id: String { fingerprint }
    public let fingerprint: String
    public let displayName: String?
    public let officialName: String?
    public let cost: Decimal?
    public let requests: Int64?
    public let tokens: Int64?

    public init(fingerprint: String, displayName: String?, officialName: String?, cost: Decimal?, requests: Int64?, tokens: Int64?) {
        self.fingerprint = fingerprint
        self.displayName = displayName
        self.officialName = officialName
        self.cost = cost
        self.requests = requests
        self.tokens = tokens
    }
}

/// Period summary (spec §79).
public struct UsageSummary: Equatable, Sendable {
    /// Nil when there is no data at all for the period.
    public let cost: Decimal?
    public let requests: Int64?
    public let tokens: Int64?
    /// False when at least one contributing record lacks amounts (honest partial data).
    public let completeAmountData: Bool
    public let daily: [DailyUsage]
    public let byAPIKey: [APIKeyUsage]

    public init(cost: Decimal?, requests: Int64?, tokens: Int64?, completeAmountData: Bool, daily: [DailyUsage], byAPIKey: [APIKeyUsage]) {
        self.cost = cost
        self.requests = requests
        self.tokens = tokens
        self.completeAmountData = completeAmountData
        self.daily = daily
        self.byAPIKey = byAPIKey
    }
}
