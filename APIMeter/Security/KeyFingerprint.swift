import CryptoKit
import Foundation

/// SHA256(API_KEY) — the only key-derived value ever persisted outside Keychain.
public enum KeyFingerprint {
    public static func sha256Hex(of apiKey: String) -> String {
        let digest = SHA256.hash(data: Data(apiKey.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    public static func displayPrefix(_ fingerprint: String, length: Int = 8) -> String {
        String(fingerprint.prefix(length))
    }
}
