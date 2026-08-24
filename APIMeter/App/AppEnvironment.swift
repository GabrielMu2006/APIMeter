import Foundation

/// Shared services container. SwiftUI views never touch SQLite or the network
/// directly - everything goes through the environment and its view models.
@MainActor
public final class AppEnvironment {
    public let database: DatabaseManager
    public let repository: UsageRepository
    public let keychain: KeychainService
    public let settings: AppSettings
    public let importService: UsageImportService
    public let alertService: BalanceAlertService
    public let balanceProvider: (String) -> BalanceProvider

    public init(database: DatabaseManager, keychain: KeychainService = KeychainService(), settings: AppSettings = .shared) {
        self.database = database
        self.repository = UsageRepository(database: database)
        self.keychain = keychain
        self.settings = settings
        self.importService = UsageImportService(repository: self.repository)
        self.alertService = BalanceAlertService()
        self.balanceProvider = { fingerprint in
            DeepSeekBalanceProvider(keychain: keychain, fingerprint: fingerprint)
        }
    }

    /// The real environment backed by the on-disk database.
    public static func live() throws -> AppEnvironment {
        AppEnvironment(database: try DatabaseManager(path: DatabaseManager.defaultLocation().path))
    }

    /// In-memory environment for unit tests.
    public static func ephemeral() throws -> AppEnvironment {
        AppEnvironment(database: try DatabaseManager.ephemeral())
    }

    public var databaseSizeBytes: Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: database.path) else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
