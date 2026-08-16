import Foundation

/// History retention choices (spec 15/84). Only affects usage_records;
/// import_batches metadata is always kept for dedup.
public enum HistoryRetention: String, CaseIterable, Sendable, Codable {
    case days30 = "30 Days"
    case days90 = "90 Days"
    case year1 = "1 Year"
    case forever = "Forever"

    public var days: Int? {
        switch self {
        case .days30: return 30
        case .days90: return 90
        case .year1: return 365
        case .forever: return nil
        }
    }
}

public enum AppearanceMode: String, CaseIterable, Sendable, Codable {
    case system
    case light
    case dark
}

/// User preferences via UserDefaults. SECURITY: never store API keys or other
/// secrets here (spec 8) - Keychain only.
public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private let defaults: UserDefaults
    private enum Keys {
        static let retention = "settings.retention"
        static let balanceThreshold = "settings.balanceThreshold"
        static let gatewayEnabled = "settings.gateway.enabled"
        static let gatewayPort = "settings.gateway.port"
        static let launchAtLogin = "settings.launchAtLogin"
        static let showDockIcon = "settings.showDockIcon"
        static let appearance = "settings.appearance"
        static let restoreWindowState = "settings.restoreWindowState"
        static let openDashboardAtLaunch = "settings.openDashboardAtLaunch"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var retention: HistoryRetention {
        get { defaults.string(forKey: Keys.retention).flatMap(HistoryRetention.init(rawValue:)) ?? .forever }
        set { defaults.set(newValue.rawValue, forKey: Keys.retention) }
    }

    /// Balance alert threshold; nil = alerts disabled.
    public var balanceAlertThreshold: Decimal? {
        get { defaults.string(forKey: Keys.balanceThreshold).flatMap(DecimalStorage.decimal) }
        set { defaults.set(newValue.map(DecimalStorage.string), forKey: Keys.balanceThreshold) }
    }

    public var gatewayEnabled: Bool {
        get { defaults.bool(forKey: Keys.gatewayEnabled) }
        set { defaults.set(newValue, forKey: Keys.gatewayEnabled) }
    }

    /// Default port per spec 20. Always validated for conflicts at start.
    public var gatewayPort: Int {
        get {
            let stored = defaults.integer(forKey: Keys.gatewayPort)
            return stored > 0 ? stored : 43123
        }
        set { defaults.set(newValue, forKey: Keys.gatewayPort) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    public var showDockIcon: Bool {
        get { defaults.object(forKey: Keys.showDockIcon) == nil ? false : defaults.bool(forKey: Keys.showDockIcon) }
        set { defaults.set(newValue, forKey: Keys.showDockIcon) }
    }

    public var appearance: AppearanceMode {
        get { defaults.string(forKey: Keys.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Keys.appearance) }
    }

    public var restoreWindowState: Bool {
        get { defaults.object(forKey: Keys.restoreWindowState) == nil ? true : defaults.bool(forKey: Keys.restoreWindowState) }
        set { defaults.set(newValue, forKey: Keys.restoreWindowState) }
    }

    public var openDashboardAtLaunch: Bool {
        get { defaults.bool(forKey: Keys.openDashboardAtLaunch) }
        set { defaults.set(newValue, forKey: Keys.openDashboardAtLaunch) }
    }
}
