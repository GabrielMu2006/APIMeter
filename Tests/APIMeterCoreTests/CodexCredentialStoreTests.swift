import Foundation
import Testing
@testable import APIMeterCore

/// Codex credential handling: JWT lifetime decoding against fixture auth
/// files, refresh merge semantics with lineage checks, and form encoding.
struct CodexCredentialStoreTests {

    /// Builds a minimal JWT (unsigned) with the given claims.
    static func makeJWT(claims: [String: Any]) -> String {
        func b64url(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = b64url(Data(#"{"alg":"none"}"#.utf8))
        let payloadData = (try? JSONSerialization.data(withJSONObject: claims)) ?? Data()
        let payload = b64url(payloadData)
        return header + "." + payload + ".sig"
    }

    static func makeHome(accessToken: String?, refreshToken: String?, accountId: String?) throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var tokens: [String: Any] = [:]
        if let accessToken { tokens["access_token"] = accessToken }
        if let refreshToken { tokens["refresh_token"] = refreshToken }
        if let accountId { tokens["account_id"] = accountId }
        let doc: [String: Any] = ["auth_mode": "chatgpt", "tokens": tokens, "last_refresh": "2026-09-16T12:18:54Z"]
        try JSONSerialization.data(withJSONObject: doc).write(to: home.appendingPathComponent("auth.json"))
        return home
    }

    @Test func availableWithJwtLifetimeAndPlan() throws {
        let exp = Date().addingTimeInterval(3600).timeIntervalSince1970
        let jwt = Self.makeJWT(claims: [
            "exp": exp,
            "https://api.openai.com/auth": ["chatgpt_plan_type": "plus"],
        ])
        let home = try Self.makeHome(accessToken: jwt, refreshToken: "rt", accountId: "acct-1")
        defer { try? FileManager.default.removeItem(at: home) }

        guard case .available(let credential) = CodexCredentialStore(homeDirectory: home).load() else {
            Issue.record("expected available")
            return
        }
        #expect(credential.accessToken == jwt)
        #expect(credential.accountId == "acct-1")
        #expect(credential.planType == "plus")
        #expect(credential.expiresAt == Date(timeIntervalSince1970: exp))
    }

    @Test func expiredByJwtClaim() throws {
        let exp = Date().addingTimeInterval(-60).timeIntervalSince1970
        let jwt = Self.makeJWT(claims: ["exp": exp])
        let home = try Self.makeHome(accessToken: jwt, refreshToken: "rt", accountId: nil)
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(CodexCredentialStore(homeDirectory: home).load() == .expired)
    }

    @Test func missingWhenNoTokens() throws {
        let home = try Self.makeHome(accessToken: nil, refreshToken: nil, accountId: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(CodexCredentialStore(homeDirectory: home).load() == .missing)
    }

    @Test func mergedPreservesUnknownFieldsAndRotates() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let object: [String: Any] = [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": NSNull(),
            "tokens": ["access_token": "old", "refresh_token": "old-rt", "id_token": "old-id", "account_id": "acct"],
        ]
        let response: [String: Any] = ["access_token": "new", "refresh_token": "new-rt", "id_token": "new-id"]
        let merged = CodexCredentialStore.merged(object: object, response: response, usedRefresh: "old-rt", now: now)
        #expect(merged != nil)
        let tokens = merged?["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "new")
        #expect(tokens?["refresh_token"] as? String == "new-rt")
        #expect(tokens?["id_token"] as? String == "new-id")
        #expect(tokens?["account_id"] as? String == "acct")
        #expect(merged?["auth_mode"] as? String == "chatgpt")
        #expect(merged?["OPENAI_API_KEY"] is NSNull)
        #expect(merged?["last_refresh"] as? String == ISO8601.string(now))
    }

    @Test func mergedRejectsLineageMismatchAndBadResponse() {
        let object: [String: Any] = ["tokens": ["access_token": "a", "refresh_token": "cli-refreshed"]]
        let response: [String: Any] = ["access_token": "b"]
        #expect(CodexCredentialStore.merged(object: object, response: response, usedRefresh: "our-rt", now: Date()) == nil)

        let goodObject: [String: Any] = ["tokens": ["access_token": "a", "refresh_token": "rt"]]
        let badResponse: [String: Any] = ["error": "server_error"]
        #expect(CodexCredentialStore.merged(object: goodObject, response: badResponse, usedRefresh: "rt", now: Date()) == nil)
    }

    @Test func refreshFormBodyEncoding() {
        let body = CodexCredentialStore.refreshFormBody(refreshToken: "a b+c")
        #expect(body.contains("client_id=" + CodexCredentialStore.clientID))
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=a%20b%2Bc"))
    }
}
