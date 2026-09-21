import Foundation

/// Which Z.ai/BigModel deployment the Coding Plan key belongs to.
/// The quota monitor endpoint exists on both; the key is region-bound.
public enum ZCodeRegion: String, CaseIterable, Sendable, Codable, Identifiable {
    case bigmodelCN = "bigmodelCN"
    case zaiGlobal = "zaiGlobal"

    public var id: String { rawValue }

    public var baseURL: URL {
        switch self {
        case .bigmodelCN: URL(string: "https://open.bigmodel.cn")!
        case .zaiGlobal: URL(string: "https://api.z.ai")!
        }
    }

    public var displayName: String {
        switch self {
        case .bigmodelCN: return "BigModel (China)"
        case .zaiGlobal: return "Z.ai (Global)"
        }
    }
}

/// Which metering window a quota limit describes.
public enum QuotaWindowKind: String, Sendable, Codable {
    case fiveHour
    case weekly
    case monthly
    /// Qoder's team-shared org resource package.
    case orgMonthly
    case monthlyTool
}

/// Traffic-light tier for a used percentage (70% / 90% thresholds, the
/// convention every community quota widget uses).
public enum QuotaHealth: Sendable {
    case green
    case orange
    case red
    case unknown

    public static func of(usedPercent: Decimal?) -> QuotaHealth {
        guard let percent = usedPercent else { return .unknown }
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .green
    }
}

/// One metering window of the Coding Plan quota (5-hour, weekly, ...).
public struct QuotaWindow: Equatable, Sendable {
    public let kind: QuotaWindowKind
    /// Used percentage as reported (0-100); nil when the server sent none.
    public let usedPercent: Decimal?
    /// Used amount in the window's own unit (tokens or credits).
    public let usedValue: Decimal?
    /// Total allowance. Note the wire field is confusingly named `usage`.
    public let totalValue: Decimal?
    public let remaining: Decimal?
    public let resetsAt: Date?
    public let modelDetails: [QuotaModelDetail]

    public init(
        kind: QuotaWindowKind,
        usedPercent: Decimal?,
        usedValue: Decimal?,
        totalValue: Decimal?,
        remaining: Decimal?,
        resetsAt: Date?,
        modelDetails: [QuotaModelDetail] = []
    ) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.usedValue = usedValue
        self.totalValue = totalValue
        self.remaining = remaining
        self.resetsAt = resetsAt
        self.modelDetails = modelDetails
    }

    public var health: QuotaHealth { QuotaHealth.of(usedPercent: usedPercent) }

    /// Remaining share of the window (0-100), derived from usedPercent.
    public var remainingPercent: Decimal? {
        usedPercent.map { Swift.max(Decimal.zero, Decimal(100) - $0) }
    }

    /// Remaining amount, preferring the server-reported value and falling
    /// back to total minus used.
    public var effectiveRemaining: Decimal? {
        if let remaining { return remaining }
        if let total = totalValue, let used = usedValue {
            return Swift.max(Decimal.zero, total - used)
        }
        return nil
    }
}

/// Per-model usage inside a window (from usageDetails).
public struct QuotaModelDetail: Equatable, Sendable {
    public let modelCode: String
    public let usage: Decimal

    public init(modelCode: String, usage: Decimal) {
        self.modelCode = modelCode
        self.usage = usage
    }
}

/// A full quota snapshot for the Coding Plan account (spec-style domain
/// value type: Decimal amounts, Date timestamps, no persistence concerns).
public struct CodingPlanQuota: Equatable, Sendable {
    /// Plan tier as reported ("lite" / "pro" / "max").
    public let planLevel: String?
    public let windows: [QuotaWindow]
    public let fetchedAt: Date

    public init(planLevel: String?, windows: [QuotaWindow], fetchedAt: Date) {
        self.planLevel = planLevel
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public var fiveHour: QuotaWindow? { windows.first { $0.kind == .fiveHour } }
    public var weekly: QuotaWindow? { windows.first { $0.kind == .weekly } }
    public var monthly: QuotaWindow? { windows.first { $0.kind == .monthly } }
    public var orgMonthly: QuotaWindow? { windows.first { $0.kind == .orgMonthly } }
    public var monthlyTool: QuotaWindow? { windows.first { $0.kind == .monthlyTool } }
}

/// Provider abstraction so business logic (and tests) never bind to the
/// concrete HTTP client - same contract as BalanceProvider.
public protocol CodingPlanQuotaProvider: Sendable {
    func fetchQuota() async throws -> CodingPlanQuota
}

extension ZhipuQuotaClient: CodingPlanQuotaProvider {}
