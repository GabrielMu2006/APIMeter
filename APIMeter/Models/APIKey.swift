import Foundation

/// Metadata of a DeepSeek API key as stored in SQLite.
/// The raw key itself is NEVER stored here — only its SHA256 fingerprint.
/// The raw key lives exclusively in the macOS Keychain.
public struct APIKey: Identifiable, Equatable, Sendable {
    public var id: Int64?
    public let fingerprint: String
    public var displayName: String?
    public var officialName: String?
    public var enabled: Bool
    public let createdAt: Date

    public init(id: Int64? = nil, fingerprint: String, displayName: String? = nil, officialName: String? = nil, enabled: Bool = true, createdAt: Date) {
        self.id = id
        self.fingerprint = fingerprint
        self.displayName = displayName
        self.officialName = officialName
        self.enabled = enabled
        self.createdAt = createdAt
    }

    /// Dashboard always prefers the local alias, then the official name.
    public var bestDisplayName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let officialName, !officialName.isEmpty { return officialName }
        return "Key " + KeyFingerprint.displayPrefix(fingerprint, length: 4)
    }
}
