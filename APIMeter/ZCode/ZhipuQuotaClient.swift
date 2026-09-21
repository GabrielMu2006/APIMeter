import Foundation

/// Thin quota-monitor client for the Z.ai / BigModel Coding Plan.
/// Holds the raw key only in memory for the duration of a request; never
/// persists or logs it.
///
/// Endpoint (cross-confirmed from the official glm-plan-usage plugin and
/// community tools; NOT an officially documented API):
///   GET {base}/api/monitor/usage/quota/limit
///   Authorization: <key>          (raw coding-plan key, no Bearer prefix)
///   Accept-Language: en-US,en
public struct ZhipuQuotaClient: Sendable {
    public let region: ZCodeRegion
    private let apiKey: String
    private let session: URLSession

    public init(region: ZCodeRegion, apiKey: String, timeout: TimeInterval = 20) {
        self.region = region
        self.apiKey = apiKey
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config)
    }

    public func fetchQuota() async throws -> CodingPlanQuota {
        var request = URLRequest(url: region.baseURL.appendingPathComponent("api/monitor/usage/quota/limit"))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.error("ZCode quota fetch network error (never logged: URL/key)")
            throw ZCodeError.network(underlying: error.localizedDescription)
        }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw ZCodeError.invalidResponse("response is not HTTP")
        }
        Log.info("ZCode quota HTTP \(http.statusCode) in \(elapsedMs)ms")

        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw ZCodeError.authenticationFailed
        case 429: throw ZCodeError.rateLimited
        default: throw ZCodeError.serverError(status: http.statusCode)
        }

        // An expired key can surface as HTTP 200 with a body-level code of
        // 401/403 - the decoder checks that after the status gate.
        return try ZhipuQuotaDecoder.decode(data: data)
    }
}
