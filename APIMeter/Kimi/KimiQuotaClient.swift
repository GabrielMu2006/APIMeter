import Foundation

/// Provider abstraction for the Kimi client (same contract as
/// CodingPlanQuotaProvider - kept separate so the two providers' error
/// types stay distinct).
public protocol KimiQuotaProviding: Sendable {
    func fetchQuota() async throws -> CodingPlanQuota
}

extension KimiQuotaClient: KimiQuotaProviding {}

/// Thin Kimi Code usage client. Holds the credential only in memory for the
/// duration of a request; never persists or logs it. We never refresh the
/// token - the Kimi CLI owns that - so an auth failure is terminal until
/// the CLI runs again.
///
/// Endpoint (mirrors the Kimi Code CLI's own traffic):
///   GET https://api.kimi.com/coding/v1/usages
///   Authorization: Bearer <token>
///   X-Msh-Platform: kimi_code_cli
///   X-Msh-Device-Id: <device id>          (when known)
public struct KimiQuotaClient: Sendable {
    public static let endpoint = URL(string: "https://api.kimi.com/coding/v1/usages")!

    private let credential: KimiCredential
    private let session: URLSession

    public init(credential: KimiCredential, timeout: TimeInterval = 20) {
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
        request.setValue("Bearer " + credential.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("kimi_code_cli", forHTTPHeaderField: "X-Msh-Platform")
        if let deviceId = credential.deviceId {
            request.setValue(deviceId, forHTTPHeaderField: "X-Msh-Device-Id")
        }

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.error("Kimi quota fetch network error (never logged: URL/token)")
            throw KimiError.network(underlying: error.localizedDescription)
        }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw KimiError.invalidResponse("response is not HTTP")
        }
        Log.info("Kimi quota HTTP \(http.statusCode) in \(elapsedMs)ms")

        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw KimiError.authenticationFailed
        case 429: throw KimiError.rateLimited
        default: throw KimiError.serverError(status: http.statusCode)
        }

        return try KimiQuotaDecoder.decode(data: data)
    }
}
