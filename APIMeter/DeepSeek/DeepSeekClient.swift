import Foundation

/// Thin DeepSeek API client. Holds the raw key only in memory for the
/// duration of a request; never persists or logs it.
public struct DeepSeekClient: Sendable {
    public static let baseURL = URL(string: "https://api.deepseek.com")!

    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, timeout: TimeInterval = 20) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config)
    }

    /// GET https://api.deepseek.com/user/balance
    public func fetchBalance() async throws -> Balance {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("user/balance"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.error("Balance fetch network error (never logged: URL/key)")
            throw DeepSeekError.network(underlying: error.localizedDescription)
        }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse("response is not HTTP")
        }
        Log.info("Balance API HTTP \(http.statusCode) in \(elapsedMs)ms")

        switch http.statusCode {
        case 200: break
        case 401: throw DeepSeekError.authenticationFailed
        case 402: throw DeepSeekError.insufficientBalance
        case 429: throw DeepSeekError.rateLimited
        default: throw DeepSeekError.serverError(status: http.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            let raw = try decoder.decode(DeepSeekBalanceResponse.self, from: data)
            return try Self.mapBalance(raw)
        } catch let error as DeepSeekError {
            throw error
        } catch {
            throw DeepSeekError.invalidResponse("unexpected JSON shape")
        }
    }

    /// Maps the official response into the internal Decimal-based Balance model.
    static func mapBalance(_ raw: DeepSeekBalanceResponse) throws -> Balance {
        let posix = Locale(identifier: "en_US_POSIX")
        let infos = try raw.balance_infos.map { info -> BalanceInfo in
            guard let total = Decimal(string: info.total_balance, locale: posix),
                  let granted = Decimal(string: info.granted_balance, locale: posix),
                  let topped = Decimal(string: info.topped_up_balance, locale: posix) else {
                throw DeepSeekError.invalidResponse("unparseable balance amounts")
            }
            return BalanceInfo(currency: info.currency, totalBalance: total, grantedBalance: granted, toppedUpBalance: topped)
        }
        return Balance(isAvailable: raw.is_available, balanceInfos: infos, fetchedAt: Date())
    }
}
