import Foundation
import Testing
import Foundation
import APIMeterCore

struct KeyFingerprintTests {

    @Test func sha256VectorIsStable() {
        // Precomputed with shasum: echo -n 'sk-1234567890abcdef' | shasum -a 256
        #expect(KeyFingerprint.sha256Hex(of: "sk-1234567890abcdef") == "DD65E03569CFA4FA17F41CC914529F60FA210B46A7EE8647C7C2F1ED5844A3EA")
    }

    @Test func differentKeysNeverCollide() {
        let a = KeyFingerprint.sha256Hex(of: "sk-aaaa")
        let b = KeyFingerprint.sha256Hex(of: "sk-bbbb")
        #expect(a != b)
        #expect(a.count == 64)
    }

    @Test func displayPrefix() {
        let fp = "ABCDEF1234567890"
        #expect(KeyFingerprint.displayPrefix(fp, length: 4) == "ABCD")
    }
}
