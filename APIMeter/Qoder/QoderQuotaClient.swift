import Foundation

/// Provider abstraction for the Qoder client (same shape as the other
/// coding-plan providers).
public protocol QoderQuotaProviding: Sendable {
    func fetchQuota() async throws -> CodingPlanQuota
}

/// Thin Qoder quota client. Holds the token only in memory for the duration
/// of a request; never persists or logs it.
///
/// Endpoint (the Qoder CLI's own traffic):
///   GET https://openapi.qoder.com.cn/api/v2/quota/usage
///   Authorization: Bearer <token from the desktop app's auth.v1.dat>
public struct QoderQuotaClient: Sendable {
    public static let endpoint = URL(string: "https://openapi.qoder.com.cn/api/v2/quota/usage")!

    private let credential: QoderCredential
    private let session: URLSession

    public init(credential: QoderCredential, timeout: TimeInterval = 20) {
        self.credential = credential
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config)
    }

    public func fetchQuota() async throws -> CodingPlanQuota {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer " + credential.token, forHTTPHeaderField: "Authorization")

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.error("Qoder quota fetch network error (never logged: URL/token)")
            throw QoderError.network(underlying: error.localizedDescription)
        }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw QoderError.invalidResponse("response is not HTTP")
        }
        Log.info("Qoder quota HTTP \(http.statusCode) in \(elapsedMs)ms")

        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw QoderError.authenticationFailed
        case 429: throw QoderError.rateLimited
        default: throw QoderError.serverError(status: http.statusCode)
        }

        return try QoderQuotaDecoder.decode(data: data)
    }
}

extension QoderQuotaClient: QoderQuotaProviding {}
