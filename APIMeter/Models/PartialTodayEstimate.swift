import Foundation

/// Lower-bound estimate of today's spend computed from the FIRST balance
/// snapshot of the day (used when no pre-midnight baseline exists).
public struct PartialTodayEstimate: Equatable, Sendable {
    public let amount: Decimal
    /// Timestamp of the first snapshot used as the start point.
    public let since: Date

    public init(amount: Decimal, since: Date) {
        self.amount = amount
        self.since = since
    }
}
