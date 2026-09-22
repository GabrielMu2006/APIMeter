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
    }

    /// Closes the day-detail sheet. Bound to the Done (X) button and Esc.
    public func closeDayDetail() {
        selectedDay = nil
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
