import Foundation

/// Shared services container. SwiftUI views never touch SQLite or the network
/// directly - everything goes through the environment and its view models.
@MainActor
public final class AppEnvironment {
    public let database: DatabaseManager
    public let repository: UsageRepository
    public let keychain: KeychainService
    /// Key pool for the ZCode / Zhipu Coding Plan key (separate Keychain service).
    public let zcodeKeychain: KeychainService
    public let settings: AppSettings
    public let importService: UsageImportService
    public let alertService: BalanceAlertService
    public let balanceProvider: (String) -> BalanceProvider
    public let quotaProvider: (ZCodeRegion, String) -> any CodingPlanQuotaProvider
    /// Kimi credential reader (the CLI's own files, read-only).
    public let kimiCredentialStore: KimiCredentialStore
    public let kimiQuotaProvider: (KimiCredential) -> any KimiQuotaProviding
    /// Qoder credential reader (the desktop app's encrypted auth file, read-only).
    public let qoderCredentialStore: QoderCredentialStore
    public let qoderQuotaProvider: (QoderCredential) -> any QoderQuotaProviding
    /// Codex credential reader (the CLI's auth.json, read-only until refresh).
    public let codexCredentialStore: CodexCredentialStore
    /// Second parameter: optional user-configured proxy for the Codex usage
    /// request (chatgpt.com is unreachable on some networks without one).
    public let codexQuotaProvider: (CodexCredential, CodexProxyConfig?) -> any CodexQuotaProviding
    /// Offline fallback: parses the rate_limits the CLI writes into its
    /// session log after every model call.
    public let codexSessionUsageReader: CodexSessionUsageReader

    public init(
        database: DatabaseManager,
        keychain: KeychainService = KeychainService(),
        settings: AppSettings = .shared,
        zcodeKeychain: KeychainService? = nil,
        quotaProvider: ((ZCodeRegion, String) -> any CodingPlanQuotaProvider)? = nil,
        kimiCredentialStore: KimiCredentialStore = KimiCredentialStore(),
        kimiQuotaProvider: ((KimiCredential) -> any KimiQuotaProviding)? = nil,
        qoderCredentialStore: QoderCredentialStore? = nil,
        qoderQuotaProvider: ((QoderCredential) -> any QoderQuotaProviding)? = nil,
        codexCredentialStore: CodexCredentialStore? = nil,
        codexQuotaProvider: ((CodexCredential, CodexProxyConfig?) -> any CodexQuotaProviding)? = nil,
        codexSessionUsageReader: CodexSessionUsageReader? = nil
    ) {
        self.database = database
        self.repository = UsageRepository(database: database)
        self.keychain = keychain
        self.zcodeKeychain = zcodeKeychain ?? KeychainService(service: KeychainService.zcodeService)
        self.settings = settings
        self.importService = UsageImportService(repository: self.repository)
        self.alertService = BalanceAlertService()
        self.balanceProvider = { fingerprint in
            DeepSeekBalanceProvider(keychain: keychain, fingerprint: fingerprint)
        }
        if let quotaProvider {
            self.quotaProvider = quotaProvider
        } else {
            self.quotaProvider = { region, key in
                ZhipuQuotaClient(region: region, apiKey: key)
            }
        }
        self.kimiCredentialStore = kimiCredentialStore
        if let kimiQuotaProvider {
            self.kimiQuotaProvider = kimiQuotaProvider
        } else {
            self.kimiQuotaProvider = { credential in
                KimiQuotaClient(credential: credential)
            }
        }
        self.qoderCredentialStore = qoderCredentialStore ?? QoderCredentialStore()
        if let qoderQuotaProvider {
            self.qoderQuotaProvider = qoderQuotaProvider
        } else {
            self.qoderQuotaProvider = { credential in
                QoderQuotaClient(credential: credential)
            }
        }
        self.codexCredentialStore = codexCredentialStore ?? CodexCredentialStore()
        if let codexQuotaProvider {
            self.codexQuotaProvider = codexQuotaProvider
        } else {
            self.codexQuotaProvider = { credential, proxy in
                CodexQuotaClient(credential: credential, proxy: proxy)
            }
        }
        self.codexSessionUsageReader = codexSessionUsageReader ?? CodexSessionUsageReader()
    }

    /// The real environment backed by the on-disk database.
    public static func live() throws -> AppEnvironment {
        AppEnvironment(database: try DatabaseManager(path: DatabaseManager.defaultLocation().path))
    }

    /// In-memory environment for unit tests (injectable provider credential
    /// stores and quota providers so tests never touch the real Keychain,
    /// network, ~/.kimi-code or the Qoder app data).
    public static func ephemeral(
        zcodeKeychain: KeychainService? = nil,
        quotaProvider: ((ZCodeRegion, String) -> any CodingPlanQuotaProvider)? = nil,
        kimiCredentialStore: KimiCredentialStore? = nil,
        kimiQuotaProvider: ((KimiCredential) -> any KimiQuotaProviding)? = nil,
        qoderCredentialStore: QoderCredentialStore? = nil,
        qoderQuotaProvider: ((QoderCredential) -> any QoderQuotaProviding)? = nil,
        codexCredentialStore: CodexCredentialStore? = nil,
        codexQuotaProvider: ((CodexCredential, CodexProxyConfig?) -> any CodexQuotaProviding)? = nil,
        codexSessionUsageReader: CodexSessionUsageReader? = nil
    ) throws -> AppEnvironment {
        AppEnvironment(
            database: try DatabaseManager.ephemeral(),
            zcodeKeychain: zcodeKeychain,
            quotaProvider: quotaProvider,
            kimiCredentialStore: kimiCredentialStore ?? KimiCredentialStore(homeDirectory: URL(fileURLWithPath: "/nonexistent-kimi-home")),
            kimiQuotaProvider: kimiQuotaProvider,
            qoderCredentialStore: qoderCredentialStore ?? QoderCredentialStore(appSupportRoot: URL(fileURLWithPath: "/nonexistent-qoder-root")),
            qoderQuotaProvider: qoderQuotaProvider,
            codexCredentialStore: codexCredentialStore ?? CodexCredentialStore(homeDirectory: URL(fileURLWithPath: "/nonexistent-codex-home")),
            codexQuotaProvider: codexQuotaProvider,
            codexSessionUsageReader: codexSessionUsageReader ?? CodexSessionUsageReader(sessionsDirectory: URL(fileURLWithPath: "/nonexistent-codex-sessions"))
        )
    }

    public var databaseSizeBytes: Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: database.path) else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
