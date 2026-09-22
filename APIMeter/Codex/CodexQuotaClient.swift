import Foundation

/// Provider abstraction for the Codex client (same shape as the other
/// coding-plan providers).
public protocol CodexQuotaProviding: Sendable {
    func fetchQuota() async throws -> CodingPlanQuota
}

/// Thin Codex usage client. Holds the token only in memory for the duration
/// of a request; never persists or logs it.
///
/// Endpoint (the Codex CLI's own ChatGPT-backend usage API):
///   GET https://chatgpt.com/backend-api/wham/usage
///   Authorization: Bearer <access token>
///   ChatGPT-Account-Id: <account id from auth.json>
public struct CodexQuotaClient: Sendable {
    public static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let credential: CodexCredential
    private let session: URLSession

    /// `proxy` routes this client's traffic through the user's local proxy
    /// (settings). nil = direct connection.
    public init(credential: CodexCredential, proxy: CodexProxyConfig? = nil, timeout: TimeInterval = 20) {
        self.credential = credential
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        if let proxy {
            config.connectionProxyDictionary = proxy.connectionProxyDictionary
            Log.info("Codex quota client using " + proxy.kind.rawValue + " proxy (host not logged)")
        }
        self.session = URLSession(configuration: config)
    }

    public func fetchQuota() async throws -> CodingPlanQuota {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer " + credential.accessToken, forHTTPHeaderField: "Authorization")
        if let accountId = credential.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.error("Codex quota fetch network error (never logged: URL/token)")
            throw CodexError.network(underlying: error.localizedDescription)
        }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw CodexError.invalidResponse("response is not HTTP")
        }
        Log.info("Codex quota HTTP \(http.statusCode) in \(elapsedMs)ms")

        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw CodexError.authenticationFailed
        case 429: throw CodexError.rateLimited
        default: throw CodexError.serverError(status: http.statusCode)
        }

        return try CodexQuotaDecoder.decode(data: data, planTypeFallback: credential.planType)
    }
}

extension CodexQuotaClient: CodexQuotaProviding {}
