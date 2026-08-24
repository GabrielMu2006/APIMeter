@preconcurrency import UserNotifications
import Foundation

/// Anti-spam state machine (spec 54):
/// - balance < threshold while not alerted -> notify once, set alerted
/// - balance keeps dropping -> no repeats
/// - balance rises to >= threshold -> re-arm
/// - drops below again -> notify again
public struct AlertStateMachine: Equatable, Sendable {
    public var alerted: Bool

    public init(alerted: Bool = false) {
        self.alerted = alerted
    }

    /// Returns true when a notification should fire.
    public mutating func evaluate(balance: Decimal, threshold: Decimal) -> Bool {
        if balance < threshold {
            if !alerted {
                alerted = true
                return true
            }
            return false
        }
        alerted = false
        return false
    }
}

/// Posts a local notification when the balance crosses the configured
/// threshold. State persists in UserDefaults; NEVER any secrets here.
@MainActor
public final class BalanceAlertService {
    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private static let stateKey = "notifications.lastAlertTriggered"

    public init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
    }

    public func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Posts an arbitrary local notification (sync failures etc.).
    public func postNotification(title: String, body: String) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "com.apimeter." + UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Checks the balance against the threshold. Returns true when it notified.
    @discardableResult
    public func check(balance: Balance?, threshold: Decimal?) async -> Bool {
        guard let threshold,
              let info = balance?.balanceInfos.first else { return false }
        var machine = AlertStateMachine(alerted: defaults.bool(forKey: Self.stateKey))
        let shouldNotify = machine.evaluate(balance: info.totalBalance, threshold: threshold)
        defaults.set(machine.alerted, forKey: Self.stateKey)
        if shouldNotify {
            let content = UNMutableNotificationContent()
            content.title = "API Meter"
            content.body = "DeepSeek balance is low. Remaining: " + CurrencyFormatter.format(info.totalBalance, currency: info.currency)
            content.sound = .default
            let request = UNNotificationRequest(identifier: "com.apimeter.balance-low", content: content, trigger: nil)
            try? await center.add(request)
        }
        return shouldNotify
    }
}
