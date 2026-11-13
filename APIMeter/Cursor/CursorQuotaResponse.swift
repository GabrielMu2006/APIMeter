import Foundation

/// Categorized Cursor quota API errors.
public enum CursorError: Error, LocalizedError, Equatable {
    case authenticationFailed
    case rateLimited
    case serverError(status: Int)
    case invalidResponse(String)
    case network(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed: return "Cursor 凭据已失效，打开 Cursor 重新登录即可"
        case .rateLimited: return "Cursor rate limited the request (429)."
        case .serverError(let status): return "Cursor server error (HTTP \(status))."
        case .invalidResponse(let reason): return "Unexpected Cursor response: \(reason)"
        case .network(let reason): return "Network error: \(reason)"
        }
    }
}

/// Raw shape of the Cursor dashboard's own usage RPC (connect-rpc JSON on
/// api2.cursor.sh, cross-confirmed from the app's proto definitions and a
/// live response). Not an officially documented API - everything is
/// defensive: protobuf int64 arrives as a STRING, every planUsage field is
/// optional.
struct CursorUsageResponse: Decodable {
    /// Epoch MILLISECONDS as a JSON string (protobuf int64 encoding).
    let billingCycleStart: FlexibleInt?
    let billingCycleEnd: FlexibleInt?
    let planUsage: PlanUsage?
    let displayMessage: String?

    struct PlanUsage: Decodable {
        /// Percent 0-100 (0.28 = "0%" in the app's own display message).
        let totalPercentUsed: Double?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
    }
}

/// Pure decoding into the shared quota domain model. The billing cycle maps
/// onto the monthly window kind (our generic long-period bucket); the UI
/// labels it "周期" rather than assuming a month.
enum CursorQuotaDecoder {

    static func decode(data: Data) throws -> CodingPlanQuota {
        let raw: CursorUsageResponse
        do {
            raw = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        } catch {
            throw CursorError.invalidResponse("unparseable JSON")
        }
        return try map(raw)
    }

    static func map(_ raw: CursorUsageResponse) throws -> CodingPlanQuota {
        let rawPercent = raw.planUsage?.totalPercentUsed
            ?? raw.planUsage?.autoPercentUsed
        guard let rawPercent else {
            throw CursorError.invalidResponse("no planUsage percentages in response")
        }
        // QuotaWindow percentages are Decimal; clamp on the Double first.
        let clamped = Swift.min(100, Swift.max(0, rawPercent))
        let usedPercent = Decimal(clamped)
        let resetsAt = raw.billingCycleEnd?.wrappedValue.map {
            Date(timeIntervalSince1970: Double($0) / 1000)
        }
        let window = QuotaWindow(
            kind: .monthly,
            usedPercent: usedPercent,
            usedValue: nil,
            totalValue: nil,
            remaining: nil,
            resetsAt: resetsAt,
            modelDetails: []
        )
        return CodingPlanQuota(planLevel: nil, windows: [window], fetchedAt: Date())
    }
}
