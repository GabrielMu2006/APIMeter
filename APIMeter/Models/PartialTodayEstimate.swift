import Foundation

/// Lower-bound estimate of today's spend computed from the FIRST balance
/// snapshot of the day (used when no pre-midnight baseline exists).
public struct PartialTodayEstimate: Equatable, Sendable {
    public let amount: Decimal
    /// Timestamp of the first snapshot used as the start point.
    public let since: Date
    /// True when at least one balance INCREASE (top-up) was detected -
    /// top-ups mask spending that happened inside the same snapshot window.
    public let topupDetected: Bool

    public init(amount: Decimal, since: Date, topupDetected: Bool) {
        self.amount = amount
        self.since = since
        self.topupDetected = topupDetected
    }
}

/// Full today estimate from a pre-midnight baseline.
public struct TodayBalanceEstimate: Equatable, Sendable {
    public let amount: Decimal
    public let topupDetected: Bool

    public init(amount: Decimal, topupDetected: Bool) {
        self.amount = amount
        self.topupDetected = topupDetected
    }
}
