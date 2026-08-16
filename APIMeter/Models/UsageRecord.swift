import Foundation

/// Trust level of a usage record (spec §25).
public enum UsageSource: String, Codable, Sendable, CaseIterable {
    /// Imported from an official DeepSeek Usage Export (highest trust).
    case officialCSV
    /// Observed by the local gateway (realtime estimate).
    case localGateway
    /// Only used for balance history, never for consumption aggregation.
    case balanceSnapshot
}

/// Whether a value has been verified against official data (spec §27).
public enum VerificationState: String, Codable, Sendable {
    case estimated
    case official
}

/// The internal standard usage model (spec §118).
/// Every data source — official CSV, local gateway — is normalized into this shape.
/// Fields that a source does not provide MUST stay nil; never fabricate values.
public struct UsageRecord: Identifiable, Equatable, Sendable {
    public var id: Int64?
    /// UTC instant of the usage event. Nil when the source only provides a date.
    public var timestamp: Date?
    /// Local-timezone day bucket ("yyyy-MM-dd" in the user's timezone at import time).
    public var day: LocalDay
    /// SHA256 fingerprint of the API key. Nil when the source does not identify a key.
    public var apiKeyFingerprint: String?
    public var model: String?

    public var requestCount: Int64?
    public var cacheHitTokens: Int64?
    public var cacheMissTokens: Int64?
    public var inputTokens: Int64?
    public var outputTokens: Int64?
    public var totalTokens: Int64?

    public var amount: Decimal?
    public var currency: String?

    public var source: UsageSource
    public var verification: VerificationState

    public init(
        id: Int64? = nil,
        timestamp: Date? = nil,
        day: LocalDay,
        apiKeyFingerprint: String? = nil,
        model: String? = nil,
        requestCount: Int64? = nil,
        cacheHitTokens: Int64? = nil,
        cacheMissTokens: Int64? = nil,
        inputTokens: Int64? = nil,
        outputTokens: Int64? = nil,
        totalTokens: Int64? = nil,
        amount: Decimal? = nil,
        currency: String? = nil,
        source: UsageSource,
        verification: VerificationState
    ) {
        self.id = id
        self.timestamp = timestamp
        self.day = day
        self.apiKeyFingerprint = apiKeyFingerprint
        self.model = model
        self.requestCount = requestCount
        self.cacheHitTokens = cacheHitTokens
        self.cacheMissTokens = cacheMissTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.amount = amount
        self.currency = currency
        self.source = source
        self.verification = verification
    }
}
