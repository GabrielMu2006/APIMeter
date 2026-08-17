import Foundation
import Observation

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
///
/// OBSERVABLE: stored properties back every preference so SwiftUI views
/// re-render immediately when a setting changes (pickles like the alert
/// threshold picker and the appearance radio group depend on this).
/// Every setter persists to UserDefaults right away.
@MainActor
@Observable
public final class AppSettings {
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
        self.retention = defaults.string(forKey: Keys.retention).flatMap(HistoryRetention.init(rawValue:)) ?? .forever
        self.balanceAlertThreshold = defaults.string(forKey: Keys.balanceThreshold).flatMap(DecimalStorage.decimal)
        self.gatewayEnabled = defaults.bool(forKey: Keys.gatewayEnabled)
        let storedPort = defaults.integer(forKey: Keys.gatewayPort)
        self.gatewayPort = storedPort > 0 ? storedPort : 43123
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.showDockIcon = defaults.object(forKey: Keys.showDockIcon) == nil ? false : defaults.bool(forKey: Keys.showDockIcon)
        self.appearance = defaults.string(forKey: Keys.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        self.restoreWindowState = defaults.object(forKey: Keys.restoreWindowState) == nil ? true : defaults.bool(forKey: Keys.restoreWindowState)
        self.openDashboardAtLaunch = defaults.bool(forKey: Keys.openDashboardAtLaunch)
    }

    public var retention: HistoryRetention {
        didSet { defaults.set(retention.rawValue, forKey: Keys.retention) }
    }

    /// Balance alert threshold; nil = alerts disabled.
    public var balanceAlertThreshold: Decimal? {
        didSet { defaults.set(balanceAlertThreshold.map(DecimalStorage.string), forKey: Keys.balanceThreshold) }
    }

    public var gatewayEnabled: Bool {
        didSet { defaults.set(gatewayEnabled, forKey: Keys.gatewayEnabled) }
    }

    /// Default port per spec 20. Always validated for conflicts at start.
    public var gatewayPort: Int {
        didSet { defaults.set(gatewayPort, forKey: Keys.gatewayPort) }
    }

    public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    public var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Keys.showDockIcon) }
    }

    public var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    public var restoreWindowState: Bool {
        didSet { defaults.set(restoreWindowState, forKey: Keys.restoreWindowState) }
    }

    public var openDashboardAtLaunch: Bool {
        didSet { defaults.set(openDashboardAtLaunch, forKey: Keys.openDashboardAtLaunch) }
    }
}
