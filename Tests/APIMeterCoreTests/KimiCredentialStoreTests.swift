import Foundation
import Testing
@testable import APIMeterCore

/// KimiCredentialStore behavior against fixture files in a temp directory:
/// available / expired (60s skew) / missing states.
struct KimiCredentialStoreTests {

    private func makeHome(token: String?, expiresAt: Double?, deviceId: String?) throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("kimi-test-" + UUID().uuidString, isDirectory: true)
        let credentials = home.appendingPathComponent("credentials", isDirectory: true)
        try FileManager.default.createDirectory(at: credentials, withIntermediateDirectories: true)
        var payload: [String: Any] = [:]
        if let token { payload["access_token"] = token }
        if let expiresAt { payload["expires_at"] = expiresAt }
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: credentials.appendingPathComponent("kimi-code.json"))
        if let deviceId {
            try deviceId.write(
                to: home.appendingPathComponent("device_id"),
                atomically: true, encoding: .utf8
            )
        }
        return home
    }

    @Test func availableCredentialWithDeviceId() throws {
        let expiresAt = Date().addingTimeInterval(10 * 60).timeIntervalSince1970
        let home = try makeHome(token: "test-token", expiresAt: expiresAt, deviceId: "device-123\n")
        defer { try? FileManager.default.removeItem(at: home) }

        let state = KimiCredentialStore(homeDirectory: home).load()
        guard case .available(let credential) = state else {
            Issue.record("expected available, got \(state)")
            return
        }
        #expect(credential.accessToken == "test-token")
        #expect(credential.deviceId == "device-123")
        #expect(credential.expiresAt == Date(timeIntervalSince1970: expiresAt))
    }

    @Test func expiredWithinSkew() throws {
        // Expiry 30s out - inside the 60s skew window, already useless.
        let expiresAt = Date().addingTimeInterval(30).timeIntervalSince1970
        let home = try makeHome(token: "test-token", expiresAt: expiresAt, deviceId: nil)
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(KimiCredentialStore(homeDirectory: home).load() == .expired)
    }

    @Test func missingWhenNoCredentialFile() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("kimi-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(KimiCredentialStore(homeDirectory: home).load() == .missing)
    }

    @Test func missingWhenTokenAbsent() throws {
        let home = try makeHome(token: nil, expiresAt: nil, deviceId: nil)
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(KimiCredentialStore(homeDirectory: home).load() == .missing)
    }

    @Test func noExpiryTreatedAsAvailable() throws {
        // The CLI has always shipped expires_at, but a file without it must
        // not read as expired - the server rejects dead tokens anyway.
        let home = try makeHome(token: "test-token", expiresAt: nil, deviceId: nil)
        defer { try? FileManager.default.removeItem(at: home) }

        guard case .available = KimiCredentialStore(homeDirectory: home).load() else {
            Issue.record("expected available")
            return
        }
    }

    @Test func mergedWritesBackRotatedTokensAndExpiry() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let object: [String: Any] = [
            "access_token": "old-access",
            "refresh_token": "old-refresh",
            "expires_at": 1,
            "token_type": "Bearer",
            "scope": "kimi-code",
        ]
        let response: [String: Any] = [
            "access_token": "new-access",
            "refresh_token": "new-refresh",
            "expires_in": 900,
            "token_type": "Bearer",
        ]
        let merged = KimiCredentialStore.merged(object: object, response: response, usedRefresh: "old-refresh", now: now)
        #expect(merged?["access_token"] as? String == "new-access")
        #expect(merged?["refresh_token"] as? String == "new-refresh")
        #expect(merged?["expires_at"] as? Int == 1_789_000_900)
        #expect(merged?["expires_in"] as? Int == 900)
        // Unknown fields survive the merge.
        #expect(merged?["scope"] as? String == "kimi-code")
    }

    @Test func mergedRejectsLineageMismatch() {
        let object: [String: Any] = ["access_token": "a", "refresh_token": "cli-refreshed"]
        let response: [String: Any] = ["access_token": "b", "refresh_token": "r2"]
        #expect(KimiCredentialStore.merged(object: object, response: response, usedRefresh: "our-refresh", now: Date()) == nil)
    }

    @Test func mergedRejectsMissingAccessToken() {
        let object: [String: Any] = ["access_token": "a", "refresh_token": "r"]
        let response: [String: Any] = ["error": "server_error"]
        #expect(KimiCredentialStore.merged(object: object, response: response, usedRefresh: "r", now: Date()) == nil)
    }

    @Test func refreshFormBodyEncoding() {
        let body = KimiCredentialStore.refreshFormBody(refreshToken: "abc def+ghi")
        #expect(body.contains("client_id=" + KimiCredentialStore.clientID))
        #expect(body.contains("grant_type=refresh_token"))
        // Strict form encoding: space -> %20, plus -> %2B (a literal +
        // would decode as a space server-side).
        #expect(body.contains("refresh_token=abc%20def%2Bghi"))
    }
}
