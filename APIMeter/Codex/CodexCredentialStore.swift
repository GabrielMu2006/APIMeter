import CommonCrypto
import Foundation
import Security

/// Credential from the Codex CLI's own auth file (~/.codex/auth.json,
/// CODEX_HOME overridable). Read-only on load; the access token is a JWT
/// with a ~10-day exp claim, so validity is checked locally without any
/// network call. When it expires, `refresh` exchanges the stored refresh
/// token at auth.openai.com and writes the ROTATED tokens back - the CLI
/// keeps working thanks to a lineage check before every write.
public struct CodexCredential: Equatable, Sendable {
    public let accessToken: String
    public let accountId: String?
    public let expiresAt: Date?
    /// ChatGPT plan tier from the JWT ("plus" / "pro" / "free" / ...).
    public let planType: String?
}

public enum CodexCredentialState: Equatable, Sendable {
    case available(CodexCredential)
    /// Token past its JWT exp and the refresh could not recover it -
    /// run `codex login` again.
    case expired
    case missing
}

public struct CodexCredentialStore: Sendable {
    private let homeDirectory: URL

    /// - Parameter homeDirectory: the Codex CLI data root. Defaults to
    ///   `CODEX_HOME` when set, otherwise `~/.codex`.
    public init(homeDirectory: URL? = nil) {
        if let homeDirectory {
            self.homeDirectory = homeDirectory
        } else if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            self.homeDirectory = URL(fileURLWithPath: override)
        } else {
            self.homeDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
    }

    public func load(now: Date = Date()) -> CodexCredentialState {
        Self.state(fromFile: Self.authFileURL(in: homeDirectory), now: now)
    }

    // MARK: - Self refresh

    /// Refreshes the expired access token at auth.openai.com and merges the
    /// rotated tokens back into auth.json. The refresh token ROTATES on
    /// use, so the write-back is mandatory; a lineage check (re-read before
    /// writing) prevents clobbering a concurrent CLI refresh.
    public func refresh(now: Date = Date()) async throws -> CodexCredentialState {
        let authURL = Self.authFileURL(in: homeDirectory)
        guard let object = Self.fileObject(at: authURL),
              let usedRefresh = (object["tokens"] as? [String: Any])?["refresh_token"] as? String,
              !usedRefresh.isEmpty
        else { return .missing }

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.refreshFormBody(refreshToken: usedRefresh).data(using: .utf8)
        let session = URLSession(configuration: .ephemeral)
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexError.invalidResponse("response is not HTTP")
        }
        let payload = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]

        if http.statusCode == 200, let payload,
           let newAccess = payload["access_token"] as? String, !newAccess.isEmpty {
            let currentObject = Self.fileObject(at: authURL)
            let currentRefresh = (currentObject?["tokens"] as? [String: Any])?["refresh_token"] as? String
            guard let currentObject, currentRefresh == usedRefresh else {
                // Lost a race against the CLI - the file already holds
                // newer tokens; report whatever is on disk now.
                return Self.state(fromFile: authURL, now: now)
            }
            guard let merged = Self.merged(object: currentObject, response: payload, usedRefresh: usedRefresh, now: now) else {
                return Self.state(fromFile: authURL, now: now)
            }
            let body = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
            let attributes = try? FileManager.default.attributesOfItem(atPath: authURL.path)
            let permissions = attributes?[.posixPermissions]
            try body.write(to: authURL, options: .atomic)
            if let permissions {
                try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: authURL.path)
            }
            return Self.state(fromFile: authURL, now: now)
        }

        if (400...401).contains(http.statusCode) {
            // invalid_grant: either the refresh token is dead or the CLI
            // refreshed concurrently and the file now holds fresh tokens.
            if case .available(let credential) = Self.state(fromFile: authURL, now: now) {
                return .available(credential)
            }
            return .expired
        }
        throw CodexError.serverError(status: http.statusCode)
    }

    // MARK: - Internals (exposed for tests)

    static func authFileURL(in home: URL) -> URL {
        home.appendingPathComponent("auth.json")
    }

    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    /// The Codex CLI's public OAuth client id (from its own binary).
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    static func refreshFormBody(refreshToken: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = refreshToken.addingPercentEncoding(withAllowedCharacters: unreserved) ?? refreshToken
        return "client_id=\(Self.clientID)&grant_type=refresh_token&refresh_token=\(encoded)"
    }

    static func fileObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Merges a token refresh response into the auth.json object. Returns
    /// nil on a lineage mismatch or a response without an access token.
    static func merged(object: [String: Any], response: [String: Any], usedRefresh: String, now: Date) -> [String: Any]? {
        var tokens = (object["tokens"] as? [String: Any]) ?? [:]
        guard (tokens["refresh_token"] as? String) == usedRefresh else { return nil }
        guard let access = response["access_token"] as? String, !access.isEmpty else { return nil }
        tokens["access_token"] = access
        if let refresh = response["refresh_token"] as? String, !refresh.isEmpty {
            tokens["refresh_token"] = refresh
        }
        if let id = response["id_token"] as? String, !id.isEmpty {
            tokens["id_token"] = id
        }
        var updated = object
        updated["tokens"] = tokens
        updated["last_refresh"] = ISO8601.string(now)
        return updated
    }

    static func state(fromFile authURL: URL, now: Date) -> CodexCredentialState {
        guard let object = fileObject(at: authURL) else { return .missing }
        return state(fromObject: object, now: now)
    }

    static func state(fromObject object: [String: Any], now: Date) -> CodexCredentialState {
        guard let tokens = object["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty
        else { return .missing }
        let expiresAt = jwtExpiration(access)
        if let expiresAt, expiresAt <= now.addingTimeInterval(Self.expirySkew) {
            return .expired
        }
        let accountId = tokens["account_id"] as? String
        let planType = jwtClaim(access, "https://api.openai.com/auth")?["chatgpt_plan_type"] as? String
        return .available(CodexCredential(accessToken: access, accountId: accountId, expiresAt: expiresAt, planType: planType))
    }

    /// Seconds of skew before a token counts as expired (5 minutes - the
    /// token lives for days, so freshness matters less than not failing
    /// mid-request).
    static let expirySkew: TimeInterval = 5 * 60

    /// Decodes a JWT payload's "exp" claim without verifying the signature
    /// (we only read lifetime metadata the issuer embedded for us).
    static func jwtExpiration(_ token: String) -> Date? {
        guard let exp = jwtClaims(token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func jwtClaim(_ token: String, _ key: String) -> [String: Any]? {
        jwtClaims(token)?[key] as? [String: Any]
    }

    static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
