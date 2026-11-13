import Foundation
import GRDB

/// Credential from the Cursor GUI app's local state database
/// (~/Library/Application Support/Cursor/User/globalStorage/state.vscdb,
/// CURSOR_STATE_DB overridable). Read-only: the access token is a WorkOS
/// JWT that lives about two months (exp claim checked locally), so unlike
/// Codex/Kimi there is no refresh flow - when it expires the user just
/// re-opens Cursor, which silently rotates the token.
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
    private let databaseURL: URL

    public init(databaseURL: URL? = nil) {
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
    }

    public func load(now: Date = Date()) -> CursorCredentialState {
        Self.state(databaseURL: databaseURL, now: now)
    }

    // MARK: - Internals (exposed for tests)

    static func state(databaseURL: URL, now: Date) -> CursorCredentialState {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return .missing }
        let token: String?
        do {
            var configuration = Configuration()
            configuration.readonly = true
            let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            token = try queue.read { db in
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
        return state(accessToken: token, now: now)
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
