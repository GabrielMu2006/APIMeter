import Foundation
import GRDB
import Testing
@testable import APIMeterCore

/// Cursor credential reading: the GUI app's state.vscdb ItemTable holds the
/// WorkOS JWT under cursorAuth/accessToken. Fixtures build real SQLite files
/// so the GRDB read path is exercised end to end (read-only mode included).
struct CursorCredentialStoreTests {

    /// Creates a state.vscdb-shaped database with the given access token.
    static func makeDatabase(directory: URL, token: String?) throws -> URL {
        let url = directory.appendingPathComponent("state.vscdb")
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
            try db.execute(sql: "INSERT INTO ItemTable (key, value) VALUES ('someOtherKey', 'unrelated')")
            if let token {
                try db.execute(sql: "INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', ?)", arguments: [token])
            }
        }
        return url
    }

    /// Builds an unsigned JWT whose payload carries the given claims
    /// (the store only reads claims, never verifies the signature).
    static func makeJWT(payload: [String: Any]) -> String {
        let encode: ([String: Any]) -> String = { object in
            let data = try! JSONSerialization.data(withJSONObject: object)
            return Data(data).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return encode(["alg": "HS256", "typ": "JWT"]) + "." + encode(payload) + ".signature"
    }

    @Test func missingDatabaseAndMissingToken() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-cred-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // No file at all.
        let store = CursorCredentialStore(databaseURL: root.appendingPathComponent("absent.vscdb"))
        #expect(store.load() == .missing)

        // Database exists but has no token row.
        let url = try Self.makeDatabase(directory: root, token: nil)
        let store2 = CursorCredentialStore(databaseURL: url)
        #expect(store2.load() == .missing)
    }

    @Test func validTokenDecodesClaimsAndExpiry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-cred-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let exp = Date().addingTimeInterval(60 * 24 * 3600).timeIntervalSince1970
        let token = Self.makeJWT(payload: [
            "aud": "https://cursor.com",
            "sub": "auth0|user_01JHCGDP15X85ST9APJJGJ34DP",
            "exp": exp,
        ])
        let url = try Self.makeDatabase(directory: root, token: token)

        guard case .available(let credential) = CursorCredentialStore(databaseURL: url).load() else {
            #expect(Bool(false), "expected .available for a valid token")
            return
        }
        #expect(credential.accessToken == token)
        #expect(credential.authId == "auth0|user_01JHCGDP15X85ST9APJJGJ34DP")
        let expected = Date(timeIntervalSince1970: exp)
        #expect(credential.expiresAt.map { abs($0.timeIntervalSince(expected)) < 1 } == true)
    }

    @Test func expiredTokenReportsExpired() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-cred-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let exp = Date().addingTimeInterval(-3600).timeIntervalSince1970
        let token = Self.makeJWT(payload: ["sub": "auth0|user_expired", "exp": exp])
        let url = try Self.makeDatabase(directory: root, token: token)
        #expect(CursorCredentialStore(databaseURL: url).load() == .expired)
    }

    @Test func garbageTokenReportsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-cred-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try Self.makeDatabase(directory: root, token: "not-a-jwt")
        #expect(CursorCredentialStore(databaseURL: url).load() == .missing)
    }
}
