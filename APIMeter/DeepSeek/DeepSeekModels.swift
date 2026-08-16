import Foundation

/// Categorized DeepSeek API errors (spec §80).
public enum DeepSeekError: Error, LocalizedError, Equatable {
    case authenticationFailed
    case insufficientBalance
    case rateLimited
    case serverError(status: Int)
    case invalidResponse(String)
    case network(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed: return "DeepSeek rejected the API key (401)."
        case .insufficientBalance: return "DeepSeek reports insufficient balance (402)."
        case .rateLimited: return "DeepSeek rate limited the request (429)."
        case .serverError(let status): return "DeepSeek server error (HTTP \(status))."
        case .invalidResponse(let reason): return "DeepSeek returned an unexpected response: \(reason)"
        case .network(let reason): return "Network error: \(reason)"
        }
    }
}

/// Raw JSON shape of GET /user/balance, per official DeepSeek API docs:
/// https://api-docs.deepseek.com/api/get-user-balance/
struct DeepSeekBalanceResponse: Decodable {
    struct BalanceInfo: Decodable {
        let currency: String
        let total_balance: String
        let granted_balance: String
        let topped_up_balance: String
    }
    let is_available: Bool
    let balance_infos: [BalanceInfo]
}
