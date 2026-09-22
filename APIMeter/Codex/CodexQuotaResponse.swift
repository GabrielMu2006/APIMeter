import Foundation

/// Categorized Codex quota API errors.
public enum CodexError: Error, LocalizedError, Equatable {
    case authenticationFailed
    case rateLimited
    case serverError(status: Int)
    case invalidResponse(String)
    case network(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed: return "Codex 凭据已失效，请运行 codex login 重新登录"
        case .rateLimited: return "OpenAI rate limited the request (429)."
        case .serverError(let status): return "OpenAI server error (HTTP \(status))."
        case .invalidResponse(let reason): return "Unexpected Codex response: \(reason)"
        case .network(let reason): return "Network error: \(reason)"
        }
    }
}

/// Raw shape of GET chatgpt.com/backend-api/wham/usage (cross-confirmed
/// from community implementations and the Codex CLI binary). Not an
/// officially documented API - everything is defensive.
struct CodexUsageResponse: Decodable {
    let rate_limit: RateLimit?
    let plan_type: String?

    struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?
    }

    struct Window: Decodable {
        let used_percent: FlexibleDecimal?
        /// Window length in seconds (18000 = 5-hour, 604800 = weekly).
        let limit_window_seconds: FlexibleInt?
        /// Epoch seconds.
        let reset_at: FlexibleDate?
    }
}

/// Pure decoding into the shared quota domain model. The two known windows
/// map onto the existing kinds (18000s -> fiveHour, 604800s -> weekly);
/// unknown window lengths are skipped rather than guessed.
enum CodexQuotaDecoder {

    static func decode(data: Data, planTypeFallback: String? = nil) throws -> CodingPlanQuota {
        let raw: CodexUsageResponse
        do {
            raw = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw CodexError.invalidResponse("unparseable JSON")
        }
        return try map(raw, planTypeFallback: planTypeFallback)
    }

    static func map(_ raw: CodexUsageResponse, planTypeFallback: String? = nil) throws -> CodingPlanQuota {
        var windows: [QuotaWindow] = []
        for window in [raw.rate_limit?.primary_window, raw.rate_limit?.secondary_window].compactMap({ $0 }) {
            guard let mapped = Self.window(window) else { continue }
            if !windows.contains(where: { $0.kind == mapped.kind }) {
                windows.append(mapped)
            }
        }
        guard !windows.isEmpty else {
            throw CodexError.invalidResponse("no usable rate-limit windows in response")
        }
        return CodingPlanQuota(
            planLevel: raw.plan_type ?? planTypeFallback,
            windows: windows,
            fetchedAt: Date()
        )
    }

    static func kind(windowSeconds: Int?) -> QuotaWindowKind? {
        guard let seconds = windowSeconds else { return nil }
        if (17_900...18_100).contains(seconds) { return .fiveHour }
        if (604_700...604_900).contains(seconds) { return .weekly }
        return nil
    }

    private static func window(_ raw: CodexUsageResponse.Window) -> QuotaWindow? {
        guard let kind = kind(windowSeconds: raw.limit_window_seconds?.wrappedValue) else { return nil }
        guard let percent = raw.used_percent?.wrappedValue else { return nil }
        return QuotaWindow(
            kind: kind,
            usedPercent: Swift.min(100, Swift.max(0, percent)),
            usedValue: nil,
            totalValue: nil,
            remaining: nil,
            resetsAt: raw.reset_at?.wrappedValue,
            modelDetails: []
        )
    }
}
