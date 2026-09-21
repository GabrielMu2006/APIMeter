import Foundation

/// Credential from the Kimi CLI's own storage (~/.kimi-code by default,
/// KIMI_CODE_HOME overridable). The Kimi CLI owns the login; API Meter
/// reads the credential and, when the ~15-minute access token expires,
/// silently refreshes it with the stored refresh token - writing the
/// rotated tokens back so the CLI keeps working (lineage-checked).
///
/// Files:
/// - credentials/kimi-code.json : {access_token, refresh_token, expires_at, ...}
///   (expires_at is epoch seconds)
/// - device_id                  : plain device id string
public struct KimiCredential: Equatable, Sendable {
    public let accessToken: String
    public let deviceId: String?
    /// Epoch-seconds expiry as reported by the credential file.
    public let expiresAt: Date?

    public init(accessToken: String, deviceId: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.deviceId = deviceId
        self.expiresAt = expiresAt
    }
}

public enum KimiCredentialState: Equatable, Sendable {
    case available(KimiCredential)
    /// No ~/.kimi-code credential at all (Kimi CLI not installed/logged in).
    case missing
    /// Token present but past its ~15-minute life; only the CLI can renew it.
    case expired
}

public struct KimiCredentialStore: Sendable {
    /// 60s skew, matching community implementations: a token about to die
    /// is already useless.
    static let expirySkew: TimeInterval = 60

    private let homeDirectory: URL

    /// - Parameter homeDirectory: the Kimi CLI data root. Defaults to
    ///   `KIMI_CODE_HOME` when set, otherwise `~/.kimi-code`.
    public init(homeDirectory: URL? = nil) {
        if let homeDirectory {
            self.homeDirectory = homeDirectory
        } else if let override = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"], !override.isEmpty {
            self.homeDirectory = URL(fileURLWithPath: override)
        } else {
            self.homeDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".kimi-code", isDirectory: true)
        }
    }

    public func load(now: Date = Date()) -> KimiCredentialState {
        Self.state(fromFile: Self.credentialFileURL(in: homeDirectory), deviceIdFile: homeDirectory.appendingPathComponent("device_id"), now: now)
    }

    // MARK: - Self refresh

    /// Refreshes the expired access token with the stored refresh token
    /// (the same call the Kimi CLI performs) and writes the rotated tokens
    /// back to the credential file.
    ///
    /// Safety rules, learned from the CLI's own flow:
    /// - the refresh token ROTATES on every use, so the response is always
    ///   written back - otherwise the CLI's stored token would be dead
    /// - a lineage check re-reads the file before writing: if the CLI
    ///   refreshed concurrently (its token on disk differs from the one we
    ///   used), we discard our result - the file already holds newer tokens
    /// - an invalid_grant rejection with an on-disk token that is somehow
    ///   fresh again is the same race, lost - report .available
    /// - invalid_grant with a stale file is terminal: only `kimi login`
    ///   can recover
    public func refresh(now: Date = Date()) async throws -> KimiCredentialState {
        let credentialURL = Self.credentialFileURL(in: homeDirectory)
        guard let data = try? Data(contentsOf: credentialURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usedRefresh = object["refresh_token"] as? String, !usedRefresh.isEmpty
        else { return .missing }

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.refreshFormBody(refreshToken: usedRefresh).data(using: .utf8)
        let session = URLSession(configuration: .ephemeral)
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KimiError.invalidResponse("response is not HTTP")
        }
        let payload = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]

        if http.statusCode == 200,
           let payload,
           let newAccess = payload["access_token"] as? String, !newAccess.isEmpty {
            // Lineage check: only write back when the file still holds the
            // refresh token we used.
            let currentObject = Self.fileObject(at: credentialURL)
            guard let currentObject, currentObject["refresh_token"] as? String == usedRefresh else {
                return Self.state(fromFile: credentialURL, deviceIdFile: Self.deviceIdFileURL(in: homeDirectory), now: now)
            }
            let merged = Self.merged(object: currentObject, response: payload, usedRefresh: usedRefresh, now: now)
            guard let merged else {
                return Self.state(fromFile: credentialURL, deviceIdFile: Self.deviceIdFileURL(in: homeDirectory), now: now)
            }
            let body = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
            let attributes = try? FileManager.default.attributesOfItem(atPath: credentialURL.path)
            let permissions = attributes?[.posixPermissions]
            try body.write(to: credentialURL, options: .atomic)
            if let permissions {
                try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: credentialURL.path)
            }
            return Self.state(fromFile: credentialURL, deviceIdFile: Self.deviceIdFileURL(in: homeDirectory), now: now)
        }

        if (400...401).contains(http.statusCode) {
            // invalid_grant: either the refresh token is dead, or the CLI
            // refreshed between our read and our request (race) and the
            // file now holds fresh tokens.
            if let currentObject = Self.fileObject(at: credentialURL),
               case .available(let credential) = Self.state(
                   fromObject: currentObject,
                   deviceIdFile: Self.deviceIdFileURL(in: homeDirectory),
                   now: now
               ) {
                return .available(credential)
            }
            return .expired
        }
        throw KimiError.serverError(status: http.statusCode)
    }

    // MARK: - Internals (exposed for tests)

    static func credentialFileURL(in home: URL) -> URL {
        home.appendingPathComponent("credentials", isDirectory: true)
            .appendingPathComponent("kimi-code.json")
    }

    static func deviceIdFileURL(in home: URL) -> URL {
        home.appendingPathComponent("device_id")
    }

    /// The Kimi Code CLI's OAuth endpoints (auth.kimi.com, its own client).
    static let tokenURL = URL(string: "https://auth.kimi.com/api/oauth/token")!
    static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"

    /// application/x-www-form-urlencoded body. Percent-encoding is strict
    /// (RFC 3986 unreserved set): a literal `+` in a token MUST become %2B,
    /// or the server decodes it as a space - URLComponents would leave it.
    static func refreshFormBody(refreshToken: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = refreshToken.addingPercentEncoding(withAllowedCharacters: unreserved) ?? refreshToken
        return "client_id=\(Self.clientID)&grant_type=refresh_token&refresh_token=\(encoded)"
    }

    static func fileObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Merges a token refresh response into the credential object.
    /// Returns nil when the lineage check fails (the file's refresh token
    /// no longer matches the one consumed by this refresh).
    static func merged(object: [String: Any], response: [String: Any], usedRefresh: String, now: Date) -> [String: Any]? {
        guard (object["refresh_token"] as? String) == usedRefresh else { return nil }
        guard let access = response["access_token"] as? String, !access.isEmpty else { return nil }
        var updated = object
        updated["access_token"] = access
        if let refresh = response["refresh_token"] as? String, !refresh.isEmpty {
            updated["refresh_token"] = refresh
        }
        let expiresIn = (response["expires_in"] as? Double)
            ?? (response["expires_in"] as? Int).map(Double.init)
            ?? 900
        updated["expires_in"] = Int(expiresIn)
        updated["expires_at"] = Int(now.timeIntervalSince1970 + expiresIn)
        if let tokenType = response["token_type"] as? String, !tokenType.isEmpty {
            updated["token_type"] = tokenType
        }
        return updated
    }

    static func state(fromFile credentialURL: URL, deviceIdFile: URL, now: Date) -> KimiCredentialState {
        guard let object = fileObject(at: credentialURL) else { return .missing }
        return state(fromObject: object, deviceIdFile: deviceIdFile, now: now)
    }

    static func state(fromObject object: [String: Any], deviceIdFile: URL, now: Date) -> KimiCredentialState {
        guard let access = object["access_token"] as? String, !access.isEmpty else { return .missing }
        let expiresAt = (object["expires_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        if let expiresAt, expiresAt.timeIntervalSince(now) <= expirySkew {
            return .expired
        }
        let rawDevice = (try? String(contentsOf: deviceIdFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceId = rawDevice.flatMap { $0.isEmpty ? nil : $0 }
        return .available(KimiCredential(accessToken: access, deviceId: deviceId, expiresAt: expiresAt))
    }
}
