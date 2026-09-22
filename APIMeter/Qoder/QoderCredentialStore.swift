import CommonCrypto
import Foundation
import Security

/// Credential from the Qoder CN desktop app. The app persists its auth as an
/// Electron SafeStorage blob (Chromium os_crypt: "v10" prefix + AES-128-CBC,
/// key = PBKDF2-SHA1 of the Keychain "Safe Storage" secret, salt "saltysalt",
/// 1003 rounds, IV = 16 spaces). API Meter decrypts it READ-ONLY; the token
/// lives ~1 month and does not rotate on use, so no refresh handling needed -
/// only a desktop-app re-login changes the file.
///
/// Files (first existing candidate dir wins):
/// - com.qodercn.app.stable / com.qoder.app.stable (Application Support)/auth.v1.dat
/// Keychain: service "Qoder CN App Safe Storage", account "Qoder CN App Key"
/// (international build: "Qoder App Safe Storage" / "Qoder App Key").
public struct QoderCredential: Equatable, Sendable {
    public let token: String
    public let expiresAt: Date?
    /// Email or name, for the settings display only.
    public let accountLabel: String?
}

public enum QoderCredentialState: Equatable, Sendable {
    case available(QoderCredential)
    /// Token past its expiresAt - re-login in the Qoder desktop app.
    case expired
    /// No Qoder desktop app data found.
    case missing
}

public struct QoderCredentialStore: Sendable {
    private let appSupportRoot: URL

    /// - Parameter appSupportRoot: Application Support root. Injectable for
    ///   tests; defaults to the user's real Application Support.
    public init(appSupportRoot: URL? = nil) {
        if let appSupportRoot {
            self.appSupportRoot = appSupportRoot
        } else {
            self.appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
    }

    static let candidateFolders = ["com.qodercn.app.stable", "com.qoder.app.stable"]
    static let candidateKeychains: [(service: String, account: String)] = [
        ("Qoder CN App Safe Storage", "Qoder CN App Key"),
        ("Qoder App Safe Storage", "Qoder App Key"),
    ]

    public func load(now: Date = Date()) -> QoderCredentialState {
        for folder in Self.candidateFolders {
            let datURL = appSupportRoot
                .appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent("auth.v1.dat")
            guard let blob = try? Data(contentsOf: datURL), !blob.isEmpty else { continue }
            for (service, account) in Self.candidateKeychains {
                guard let password = Self.keychainSecret(service: service, account: account) else { continue }
                guard let plain = QoderCredentialCrypto.decrypt(dat: blob, password: password),
                      let object = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any],
                      let token = object["token"] as? String, !token.isEmpty
                else { continue }
                let expiresAt = Self.parseDate(object["expiresAt"])
                if let expiresAt, expiresAt <= now {
                    return .expired
                }
                let label = (object["user"] as? [String: Any]).flatMap { user in
                    (user["email"] as? String) ?? (user["name"] as? String)
                }
                return .available(QoderCredential(token: token, expiresAt: expiresAt, accountLabel: label))
            }
            // Found the file but could not decrypt with any known keychain
            // entry - stop looking, the user must re-login the desktop app.
            return .missing
        }
        return .missing
    }

    static func keychainSecret(service: String, account: String) -> String? {
        SafeStorageSecretCache.shared.secret(service: service, account: account)
    }

    /// ISO-8601 timestamp as stored by the desktop app ("2026-10-18T10:26:07Z").
    static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        if let date = ISO8601.date(string) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try? formatter.date(from: string)
    }
}

/// Per-process memoization for the Safe Storage keychain secret.
///
/// Reading ANOTHER app's keychain item can require the login password, and
/// the "Always Allow" grant is tied to the app's code signature - an ad-hoc
/// rebuilt binary never sticks in the item's ACL, so without memoization
/// every quota refresh would re-prompt (the "password storm"). Rules:
/// - a successful secret is cached for the process lifetime
/// - an interactive failure (password required, user cancelled) marks the
///   entry denied so this launch never touches the keychain for it again
/// - plain "item not found" is cheap and prompt-free, retried as normal
private final class SafeStorageSecretCache: @unchecked Sendable {
    static let shared = SafeStorageSecretCache()

    private let lock = NSLock()
    private var secrets: [String: String] = [:]
    private var deniedKeys: Set<String> = []

    func secret(service: String, account: String) -> String? {
        let key = service + "|" + account
        lock.lock()
        if deniedKeys.contains(key) {
            lock.unlock()
            return nil
        }
        if let cached = secrets[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            let value = (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
            if let value {
                lock.lock()
                secrets[key] = value
                lock.unlock()
            }
            return value
        case errSecAuthFailed, errSecInteractionRequired, errSecUserCanceled:
            // The user was (or would be) prompted and it did not succeed -
            // stop asking for this entry until the next launch.
            lock.lock()
            deniedKeys.insert(key)
            lock.unlock()
            return nil
        default:
            // errSecItemNotFound and friends: no prompt involved.
            return nil
        }
    }
}

/// Chromium os_crypt primitives (macOS variant).
enum QoderCredentialCrypto {
    static let salt = Array("saltysalt".utf8)
    static let iterations: UInt32 = 1_003
    static let iv = [UInt8](repeating: 0x20, count: 16)

    static func derivedKey(password: String) -> [UInt8]? {
        var derived = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let status = password.withCString { passwordBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes, password.utf8.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                iterations,
                &derived, derived.count
            )
        }
        return status == kCCSuccess ? derived : nil
    }

    /// Decrypts an Electron SafeStorage blob ("v10" + AES-128-CBC/PKCS7).
    static func decrypt(dat: Data, password: String) -> Data? {
        guard dat.prefix(3) == Data("v10".utf8) else { return nil }
        guard let key = derivedKey(password: password) else { return nil }
        let cipher = dat.dropFirst(3)
        guard !cipher.isEmpty, cipher.count % 16 == 0 else { return nil }
        var output = Data(count: cipher.count + kCCBlockSizeAES128)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outPtr in
            cipher.withUnsafeBytes { inPtr in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES128),
                    CCOptions(kCCOptionPKCS7Padding),
                    key, key.count,
                    iv,
                    inPtr.baseAddress, inPtr.count,
                    outPtr.baseAddress, outPtr.count,
                    &moved
                )
            }
        }
        guard status == kCCSuccess, moved > 0 else { return nil }
        return output.prefix(moved)
    }
}
