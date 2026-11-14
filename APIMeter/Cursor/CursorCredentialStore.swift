import Foundation
import GRDB
import Security

/// Credential from the Cursor GUI app's local state database
/// (~/Library/Application Support/Cursor/User/globalStorage/state.vscdb,
/// CURSOR_STATE_DB overridable). Read-only: the access token is a WorkOS
/// JWT that lives about two months (exp claim checked locally), so unlike
/// Codex/Kimi there is no refresh flow - when it expires the user just
/// re-opens Cursor, which silently rotates the token.
///
/// Storage format depends on the Cursor version: older builds keep the
/// plaintext JWT; Cursor 3.30+ wraps it as
/// "cursor-safe-storage:v1:" + base64(Chromium os_crypt "v10" + AES-128-CBC)
/// - the same SafeStorage scheme Qoder uses, with the AES key derived from
/// the keychain item "Cursor Safe Storage"/"Cursor Key".
public struct CursorCredential: Equatable, Sendable {
    public let accessToken: String
    /// WorkOS subject, "auth0|user_..." - the user id the usage RPC takes.
    public let authId: String?
    public let expiresAt: Date?
}

public enum CursorCredentialState: Equatable, Sendable {
    case available(CursorCredential)
    /// Token past its JWT exp - open Cursor once to re-login.
    case expired
    case missing
}

public struct CursorCredentialStore: Sendable {
    public static let safeStoragePrefix = "cursor-safe-storage:v1:"
    public static let safeStorageService = "Cursor Safe Storage"
    public static let safeStorageAccount = "Cursor Key"

    private let databaseURL: URL
    /// Injectable so tests exercise the SafeStorage path without the
    /// real keychain. Defaults to the process-level memoized reader
    /// (at most one password prompt per launch, like Qoder).
    private let safeStorageSecret: @Sendable (_ service: String, _ account: String) -> String?

    public init(databaseURL: URL? = nil, safeStorageSecret: (@Sendable (String, String) -> String?)? = nil) {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else if let override = ProcessInfo.processInfo.environment["CURSOR_STATE_DB"], !override.isEmpty {
            self.databaseURL = URL(fileURLWithPath: override)
        } else {
            self.databaseURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("Cursor", isDirectory: true)
                .appendingPathComponent("User/globalStorage/state.vscdb")
        }
        self.safeStorageSecret = safeStorageSecret ?? { service, account in
            SafeStorageSecretCache.shared.secret(service: service, account: account)
        }
    }

    public func load(now: Date = Date()) -> CursorCredentialState {
        Self.state(databaseURL: databaseURL, now: now, safeStorageSecret: safeStorageSecret)
    }

    // MARK: - Internals (exposed for tests)

    static func state(databaseURL: URL, now: Date, safeStorageSecret: (String, String) -> String?) -> CursorCredentialState {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return .missing }
        let storedValue: String?
        do {
            var configuration = Configuration()
            configuration.readonly = true
            let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            storedValue = try queue.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT value FROM ItemTable WHERE key = ?",
                    arguments: ["cursorAuth/accessToken"]
                )
                return row?["value"] as? String
            }
        } catch {
            // A locked or unreadable database is a "missing" steady state,
            // not an error banner - the next refresh retries anyway.
            return .missing
        }
        let token = Self.plainAccessToken(from: storedValue, safeStorageSecret: safeStorageSecret)
        return state(accessToken: token, now: now)
    }

    /// Unwraps the SafeStorage envelope when present, passes plaintext
    /// JWTs through. Returns nil when the envelope is there but the
    /// keychain secret is unavailable (prompt denied / circuit broken) -
    /// a retriable steady state, not an error banner.
    static func plainAccessToken(from storedValue: String?, safeStorageSecret: (String, String) -> String?) -> String? {
        guard let storedValue, !storedValue.isEmpty else { return nil }
        guard storedValue.hasPrefix(safeStoragePrefix) else { return storedValue }
        let encoded = storedValue.dropFirst(safeStoragePrefix.count)
        guard let blob = Data(base64Encoded: String(encoded)) else { return nil }
        guard let password = safeStorageSecret(safeStorageService, safeStorageAccount) else { return nil }
        guard let decrypted = QoderCredentialCrypto.decrypt(dat: blob, password: password) else { return nil }
        return String(data: decrypted, encoding: .utf8)
    }

    static func state(accessToken: String?, now: Date) -> CursorCredentialState {
        guard let accessToken, !accessToken.isEmpty else { return .missing }
        guard let payload = jwtClaims(accessToken) else { return .missing }
        let authId = payload["sub"] as? String
        if let exp = payload["exp"] as? Double,
           Date(timeIntervalSince1970: exp) <= now.addingTimeInterval(Self.expirySkew) {
            return .expired
        }
        return .available(CursorCredential(accessToken: accessToken, authId: authId, expiresAt: jwtExpiration(accessToken)))
    }

    /// Seconds of skew before a token counts as expired (5 minutes).
    static let expirySkew: TimeInterval = 5 * 60

    static func jwtExpiration(_ token: String) -> Date? {
        guard let exp = jwtClaims(token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
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
