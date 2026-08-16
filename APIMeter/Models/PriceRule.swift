import Foundation

/// Pricing period marker (e.g. DeepSeek off-peak discounts).
public enum PricePeriod: String, Codable, Sendable, CaseIterable {
    case standard
    case offPeak
}

/// A versioned pricing rule for one model (spec §29/§30).
/// Prices are per 1M tokens. Never hardcode prices in business code —
/// rules live in SQLite and match requests by timestamp.
public struct PriceRule: Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var provider: String
    public var model: String
    public var effectiveFrom: Date
    public var effectiveTo: Date?
    public var period: PricePeriod?
    public var cacheHitPrice: Decimal?
    public var cacheMissPrice: Decimal?
    public var outputPrice: Decimal?
    public var currency: String

    public init(
        id: Int64? = nil,
        provider: String = "deepseek",
        model: String,
        effectiveFrom: Date,
        effectiveTo: Date? = nil,
        period: PricePeriod? = nil,
        cacheHitPrice: Decimal? = nil,
        cacheMissPrice: Decimal? = nil,
        outputPrice: Decimal? = nil,
        currency: String
    ) {
        self.id = id
        self.provider = provider
        self.model = model
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.period = period
        self.cacheHitPrice = cacheHitPrice
        self.cacheMissPrice = cacheMissPrice
        self.outputPrice = outputPrice
        self.currency = currency
    }
}
