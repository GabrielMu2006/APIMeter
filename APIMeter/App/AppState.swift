import Foundation
import Observation

/// Root observable state shared by menu bar, dashboard and settings.
@MainActor
@Observable
public final class AppState {
    public let environment: AppEnvironment
    public var balanceViewModel: BalanceViewModel
    public var dashboardViewModel: DashboardViewModel
    public var settingsViewModel: SettingsViewModel
    public var selectedDay: LocalDay?
    /// Strong: the controller owns the NSPanel for the app's lifetime.
    public var floatingPanelController: FloatingPanelController?
    public weak var refreshCoordinator: RefreshCoordinator?
    public weak var syncScheduler: SyncScheduler?
    /// Set after creation so AppDelegate and shortcuts can reach the state.
    public nonisolated(unsafe) static var current: AppState?

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.balanceViewModel = BalanceViewModel(environment: environment)
        self.dashboardViewModel = DashboardViewModel(environment: environment)
        self.settingsViewModel = SettingsViewModel(environment: environment)
    }

    /// Menu bar / shortcut entry: show or hide the floating dashboard.
    public func toggleDashboard() {
        floatingPanelController?.toggle()
    }

    public func showMini() {
        floatingPanelController?.show(mode: .mini)
    }

    public func notePanelShown() {
        refreshCoordinator?.notePanelVisibilityChanged(visible: true)
    }

    public func notePanelHidden() {
        refreshCoordinator?.notePanelVisibilityChanged(visible: false)
    }

    /// Refresh everything the UI needs (balance + usage aggregates).
    public func refreshAll() async {
        await balanceViewModel.refresh()
        await dashboardViewModel.reload()
    }
}
