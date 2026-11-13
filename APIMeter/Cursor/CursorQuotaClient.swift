import Foundation

/// Provider abstraction for the Cursor client (same shape as the other
/// coding-plan providers).
public protocol CursorQuotaProviding: Sendable {
    func fetchQuota() async throws -> CodingPlanQuota
}

/// Thin Cursor usage client. The endpoint is the dashboard's own
/// connect-rpc on api2.cursor.sh - discovered from the app's proto
/// definitions (aiserver.v1.DashboardService/GetCurrentPeriodUsage),
/// confirmed live with the GUI token. Holds the token only in memory for
/// the duration of a request; never persists or logs it.
public struct CursorQuotaClient: Sendable {
    static let endpoint = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    /// A neutral UA passes Cloudflare; the default URLSession UA does not.
    static let userAgent = "APIMeter/1.6 (macOS)"

    private let credential: CursorCredential
    private let session: URLSession

    public init(credential: CursorCredential, timeout: TimeInterval = 20) {
        self.credential = credential
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Connect-Protocol-Version": "1",
        ]
        self.session = URLSession(configuration: config)
    }

    public func fetchQuota() async throws -> CodingPlanQuota {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer " + credential.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["includePooledUsage": true])

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.error("Cursor quota fetch network error (never logged: URL/token)")
            throw CursorError.network(underlying: error.localizedDescription)
        }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw CursorError.invalidResponse("response is not HTTP")
        }
        Log.info("Cursor quota HTTP \(http.statusCode) in \(elapsedMs)ms")

        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw CursorError.authenticationFailed
        case 429: throw CursorError.rateLimited
        default: throw CursorError.serverError(status: http.statusCode)
        }

        return try CursorQuotaDecoder.decode(data: data)
    }
}

extension CursorQuotaClient: CursorQuotaProviding {}
