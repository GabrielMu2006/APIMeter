import Foundation
import Security

public enum KeychainError: Error, LocalizedError, Equatable {
    case emptyKey
    case itemNotFound
    case unreadableData
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptyKey: return "API key is empty."
        case .itemNotFound: return "No API key stored in Keychain for this fingerprint."
        case .unreadableData: return "Keychain item data could not be read."
        case .unexpectedStatus(let status): return "Keychain operation failed with status \(status)."
        }
    }
}

/// Stores provider API keys in the macOS Keychain (spec §8).
/// - Raw keys are held only briefly in memory and only ever persisted in Keychain.
/// - SQLite stores only SHA256 fingerprints (KeyFingerprint).
/// - Items are keyed by account = "fingerprint:<SHA256>" so multiple API keys
///   are supported and re-saving the same key is idempotent.
/// - One Keychain *service* per provider (DeepSeek, ZCode Coding Plan) so
///   their key pools never mix.
public struct KeychainService: Sendable {
    public static let deepSeekService = "com.apimeter.deepseek-api-keys"
    public static let zcodeService = "com.apimeter.zhipu-coding-plan-key"
    public static let accountPrefix = "fingerprint:"

    private let service: String

    /// DeepSeek key pool by default (existing behavior).
    public init() {
        self.init(service: Self.deepSeekService)
    }

    public init(service: String) {
        self.service = service
    }

    /// Saves the key and returns its fingerprint.
    public func saveAPIKey(_ rawKey: String) throws -> String {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw KeychainError.emptyKey }
        let fingerprint = KeyFingerprint.sha256Hex(of: key)
        let account = Self.accountPrefix + fingerprint

        // Idempotent re-save: remove any existing item first.
        try? deleteAPIKey(fingerprint: fingerprint)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrLabel as String: "API Meter — DeepSeek API Key (••••\(KeyFingerprint.displayPrefix(fingerprint, length: 4)))",
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        Log.info("API key saved to Keychain (fingerprint \(KeyFingerprint.displayPrefix(fingerprint))…)")
        return fingerprint
    }

    public func readAPIKey(fingerprint: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.accountPrefix + fingerprint,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeychainError.itemNotFound }
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw KeychainError.unreadableData
        }
        return key
    }

    public func deleteAPIKey(fingerprint: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.accountPrefix + fingerprint,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// All stored fingerprints, sorted.
    public func listFingerprints() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return [] }
            throw KeychainError.unexpectedStatus(status)
        }
        guard let items = item as? [[String: Any]] else { return [] }
        let prefix = Self.accountPrefix
        return items.compactMap { dict in
            (dict[kSecAttrAccount as String] as? String)
                .flatMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
        }.sorted()
    }
}
