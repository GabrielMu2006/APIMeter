import Foundation
import Testing
import Foundation
import APIMeterCore

struct KeychainServiceTests {

    @Test func roundtripAndCleanup() throws {
        let service = KeychainService()
        let synthetic = "sk-test-keychain-" + UUID().uuidString
        let fingerprint = try service.saveAPIKey(synthetic)
        #expect(fingerprint.count == 64)
        #expect(try service.readAPIKey(fingerprint: fingerprint) == synthetic)
        let list = try service.listFingerprints()
        #expect(list.contains(fingerprint))
        try service.deleteAPIKey(fingerprint: fingerprint)
        #expect(try service.listFingerprints().contains(fingerprint) == false)
    }

    @Test func saveIsIdempotent() throws {
        let service = KeychainService()
        let key = "sk-test-keychain-" + UUID().uuidString
        let f1 = try service.saveAPIKey(key)
        let f2 = try service.saveAPIKey(key)
        #expect(f1 == f2)
        #expect(try service.readAPIKey(fingerprint: f1) == key)
        try service.deleteAPIKey(fingerprint: f1)
    }

    @Test func emptyKeyRejected() {
        let service = KeychainService()
        #expect(throws: KeychainError.self) {
            _ = try service.saveAPIKey("   ")
        }
    }
}
