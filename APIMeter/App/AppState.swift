import AppKit
import Foundation
import Observation

/// Root observable state shared by menu bar, dashboard and settings.
@MainActor
@Observable
public final class AppState {
    public let environment: AppEnvironment
    public var balanceViewModel: BalanceViewModel
    public var zcodeQuotaViewModel: ZCodeQuotaViewModel
    public var kimiQuotaViewModel: KimiQuotaViewModel
    public var qoderQuotaViewModel: QoderQuotaViewModel
    public var codexQuotaViewModel: CodexQuotaViewModel
    public var dashboardViewModel: DashboardViewModel
    public var settingsViewModel: SettingsViewModel
    public var selectedDay: LocalDay?
    /// Strong: the controller owns the NSPanel for the app's lifetime.
    public var floatingPanelController: FloatingPanelController?
    /// Strong: the desktop widget panel (quota + balance cards), owned for
    /// the app's lifetime like the floating dashboard panel.
    public var widgetPanelController: WidgetPanelController?
    public weak var refreshCoordinator: RefreshCoordinator?
    /// STRONG: the daily sync scheduler must live for the app's lifetime
    /// (AppDelegate only holds it as a local). A weak reference here would
    /// let it deallocate right after launch (Codex review P0).
    public var syncScheduler: SyncScheduler?
    /// One-click setup of the DeepSeekSync CLI (launch prompt + Settings UI).
    public var syncInstaller: DeepSeekSyncInstaller?
    /// Writes the widget snapshot file for the WidgetKit extension and
    /// reloads its timelines when any view model reports fresh data.
    private let widgetStateStore = WidgetStateStore()
    /// nonisolated(unsafe): only touched from init and deinit (deinit runs
    /// after all other references are gone, so there is no data race).
    private nonisolated(unsafe) var widgetStateObserver: NSObjectProtocol?
    /// Set after creation so AppDelegate and shortcuts can reach the state.
    public nonisolated(unsafe) static var current: AppState?

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.balanceViewModel = BalanceViewModel(environment: environment)
        self.zcodeQuotaViewModel = ZCodeQuotaViewModel(environment: environment)
        self.kimiQuotaViewModel = KimiQuotaViewModel(environment: environment)
        self.qoderQuotaViewModel = QoderQuotaViewModel(environment: environment)
        self.codexQuotaViewModel = CodexQuotaViewModel(environment: environment)
        self.dashboardViewModel = DashboardViewModel(environment: environment)
        self.settingsViewModel = SettingsViewModel(environment: environment)
        self.widgetStateObserver = widgetStateStore.observeAndPublish { [weak self] in
            self?.widgetSnapshot() ?? WidgetSnapshot(writtenAt: Date(), balance: nil, providers: [])
        }
    }

    deinit {
        widgetStateObserver.map { NotificationCenter.default.removeObserver($0) }
    }

    /// Everything the WidgetKit extension renders, gathered from the view
    /// models' latest data (no network work here).
    public func widgetSnapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            writtenAt: Date(),
            balance: widgetBalanceInfo(),
            providers: [
                widgetProvider("zcode", "ZCode", zcodeQuotaViewModel.quota, offline: false),
                widgetProvider("kimi", "Kimi", kimiQuotaViewModel.quota, offline: false),
                widgetProvider("qoder", "Qoder", qoderQuotaViewModel.quota, offline: false),
                widgetProvider("codex", "Codex", codexQuotaViewModel.quota, offline: codexQuotaViewModel.usingSessionFallback),
            ]
        )
    }

    private func widgetBalanceInfo() -> WidgetSnapshot.BalanceInfo? {
        guard let balance = balanceViewModel.balance else { return nil }
        guard let info = balance.info(for: "CNY") ?? balance.balanceInfos.first else { return nil }
        return WidgetSnapshot.BalanceInfo(
            total: info.totalBalance,
            currency: info.currency,
            today: dashboardViewModel.todayDisplayCost,
            isAvailable: balance.isAvailable,
            fetchedAt: balance.fetchedAt
        )
    }

    func widgetProvider(_ id: String, _ name: String, _ quota: CodingPlanQuota?, offline: Bool) -> WidgetSnapshot.ProviderInfo {
        guard let quota else {
            return WidgetSnapshot.ProviderInfo(id: id, displayName: name, available: false, offline: false, planLevel: nil, fetchedAt: nil, windows: [])
        }
        return WidgetSnapshot.ProviderInfo(
            id: id,
            displayName: name,
            available: true,
            offline: offline,
            planLevel: quota.planLevel,
            fetchedAt: quota.fetchedAt,
            windows: quota.windows.map { window in
                WidgetSnapshot.WindowInfo(
                    kind: window.kind.rawValue,
                    remainingPercent: window.remainingPercent.map { NSDecimalNumber(decimal: $0).doubleValue },
                    remainingLabel: window.effectiveRemaining.map(QuotaWidgetCard.compact),
                    resetsAt: window.resetsAt
                )
            }
        )
    }

    /// Closes the day-detail sheet. Bound to the Done (X) button and Esc.
    public func closeDayDetail() {
        selectedDay = nil
    }

    /// Opens the Settings window from the floating panels. SwiftUI's
    /// openSettings() environment action is only wired inside scene-hosted
    /// views (the panels host their content manually), so this triggers the
    /// main menu's own "Settings…" item - whatever selector SwiftUI uses on
    /// this OS version is already installed there.
    public func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Route A: the standard app-menu item SwiftUI installed for the
        // Settings scene (matched by action or by Cmd+, key equivalent).
        var handled = false
        if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu {
            let item = appMenu.items.first { item in
                item.action == Selector(("showSettingsWindow:"))
                    || item.action == Selector(("showSettings:"))
                    || item.keyEquivalent == "," && item.keyEquivalentModifierMask.contains(.command)
            }
            if let item, item.action != nil {
                Log.info("Settings: routing via app menu item '\(item.title)'")
                NSApp.sendAction(item.action!, to: item.target, from: item)
                handled = true
            }
        }

        // Route B: direct legacy selectors.
        if !handled {
            for action in [Selector(("showSettingsWindow:")), Selector(("showSettings:"))] {
                if NSApp.sendAction(action, to: nil, from: nil) {
                    Log.info("Settings: routed via direct selector")
                    handled = true
                    break
                }
            }
        }
        if !handled {
            Log.error("Settings: no responder for any settings action")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApp.activate(ignoringOtherApps: true)
            let windows = NSApp.windows.map { "\($0.title)|\($0.identifier?.rawValue ?? "-")|level=\($0.level.rawValue)|visible=\($0.isVisible)" }
            Log.info("Settings: windows now: " + windows.joined(separator: " ; "))
            for window in NSApp.windows where Self.isSettingsWindow(window) {
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
                Log.info("Settings: raised settings window")
            }
        }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        let identifier = (window.identifier?.rawValue ?? "").lowercased()
        let title = window.title.lowercased()
        return identifier.contains("settings") || title.contains("settings") || window.title == "设置"
    }

    /// Menu bar / shortcut entry: show or hide the floating dashboard.
    public func toggleDashboard() {
        floatingPanelController?.toggle()
    }

    public func notePanelShown() {
        refreshCoordinator?.notePanelVisibilityChanged(visible: true)
    }

    public func notePanelHidden() {
        refreshCoordinator?.notePanelVisibilityChanged(visible: false)
    }

    /// Refresh everything the UI needs (balance + quotas + usage aggregates).
    /// All quota refreshes self-throttle to one network call per 5 minutes.
    public func refreshAll() async {
        await balanceViewModel.refresh()
        await zcodeQuotaViewModel.refresh()
        await kimiQuotaViewModel.refresh()
        await qoderQuotaViewModel.refresh()
        await codexQuotaViewModel.refresh()
        await dashboardViewModel.reload()
    }
}
