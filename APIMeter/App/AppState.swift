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

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.balanceViewModel = BalanceViewModel(environment: environment)
        self.dashboardViewModel = DashboardViewModel(environment: environment)
        self.settingsViewModel = SettingsViewModel(environment: environment)
    }

    /// Refresh everything the UI needs (balance + usage aggregates).
    public func refreshAll() async {
        await balanceViewModel.refresh()
        await dashboardViewModel.reload()
    }
}
