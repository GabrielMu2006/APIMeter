import Foundation

/// Categorized Qoder quota API errors.
public enum QoderError: Error, LocalizedError, Equatable {
    case authenticationFailed
    case rateLimited
    case serverError(status: Int)
    case invalidResponse(String)
    case network(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed: return "Qoder 凭据已失效，请在 Qoder 桌面版重新登录"
        case .rateLimited: return "Qoder rate limited the request (429)."
        case .serverError(let status): return "Qoder server error (HTTP \(status))."
        case .invalidResponse(let reason): return "Unexpected Qoder response: \(reason)"
        case .network(let reason): return "Network error: \(reason)"
        }
    }
}

/// Raw shape of GET /api/v2/quota/usage (cross-checked against live traffic).
/// The team plan exposes two credit pools: the member's personal monthly
/// quota and the org resource package. `percentage` has an ambiguous scale
/// in the wild - we always derive it from used/total instead.
struct QoderQuotaResponse: Decodable {
    let userType: String?
    let isQuotaExceeded: Bool?
    /// Epoch milliseconds.
    let expiresAt: FlexibleDate?
    let userQuota: Pool?
    let orgResourcePackage: Pool?

    struct Pool: Decodable {
        let total: FlexibleDecimal?
        let used: FlexibleDecimal?
        let remaining: FlexibleDecimal?
        let unit: String?
        /// Org pools only; absent on the personal quota.
        let available: Bool?
    }
}

/// Pure decoding into the shared quota domain model.
/// Personal pool -> .monthly; org pool -> .orgMonthly (only when available).
enum QoderQuotaDecoder {

    static func decode(data: Data) throws -> CodingPlanQuota {
        let raw: QoderQuotaResponse
        do {
            raw = try JSONDecoder().decode(QoderQuotaResponse.self, from: data)
        } catch {
            throw QoderError.invalidResponse("unparseable JSON")
        }
        return try map(raw)
    }

    static func map(_ raw: QoderQuotaResponse) throws -> CodingPlanQuota {
        var windows: [QuotaWindow] = []
        if let personal = Self.poolWindow(raw.userQuota, kind: .monthly, resetsAt: raw.expiresAt?.wrappedValue) {
            windows.append(personal)
        }
        if let org = raw.orgResourcePackage, org.available == true,
           let window = Self.poolWindow(org, kind: .orgMonthly, resetsAt: raw.expiresAt?.wrappedValue) {
            windows.append(window)
        }
        guard !windows.isEmpty else {
            throw QoderError.invalidResponse("no usable quota pools in response")
        }
        return CodingPlanQuota(planLevel: raw.userType?.capitalized, windows: windows, fetchedAt: Date())
    }

    private static func poolWindow(_ pool: QoderQuotaResponse.Pool?, kind: QuotaWindowKind, resetsAt: Date?) -> QuotaWindow? {
        guard let pool else { return nil }
        let total = pool.total?.wrappedValue
        let used = pool.used?.wrappedValue
        let remaining = pool.remaining?.wrappedValue
        guard let total, total > 0 else {
            // A zero pool is still a window when usage exists; otherwise
            // there is nothing meaningful to show.
            guard let used, used > 0 else { return nil }
            return QuotaWindow(kind: kind, usedPercent: 100, usedValue: used, totalValue: 0, remaining: 0, resetsAt: resetsAt, modelDetails: [])
        }
        let percent = used.map { Swift.min(100, Swift.max(0, ($0 / total) * 100)) }
        let effectiveRemaining = remaining ?? Swift.max(0, total - (used ?? 0))
        return QuotaWindow(
            kind: kind,
            usedPercent: percent,
            usedValue: used,
            totalValue: total,
            remaining: effectiveRemaining,
            resetsAt: resetsAt,
            modelDetails: []
        )
    }
}
