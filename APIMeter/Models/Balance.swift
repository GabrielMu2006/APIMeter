import Foundation

/// One currency entry of the DeepSeek balance API response.
public struct BalanceInfo: Equatable, Sendable {
    public let currency: String
    public let totalBalance: Decimal
    public let grantedBalance: Decimal
    public let toppedUpBalance: Decimal

    public init(currency: String, totalBalance: Decimal, grantedBalance: Decimal, toppedUpBalance: Decimal) {
        self.currency = currency
        self.totalBalance = totalBalance
        self.grantedBalance = grantedBalance
        self.toppedUpBalance = toppedUpBalance
    }
}

/// Account balance as returned by the DeepSeek balance API.
/// Amounts are Decimal per project rules (never Double).
public struct Balance: Equatable, Sendable {
    public let isAvailable: Bool
    public let balanceInfos: [BalanceInfo]
    public let fetchedAt: Date

    public init(isAvailable: Bool, balanceInfos: [BalanceInfo], fetchedAt: Date) {
        self.isAvailable = isAvailable
        self.balanceInfos = balanceInfos
        self.fetchedAt = fetchedAt
    }

    public func info(for currency: String) -> BalanceInfo? {
        balanceInfos.first { $0.currency.caseInsensitiveCompare(currency) == .orderedSame }
    }
}
