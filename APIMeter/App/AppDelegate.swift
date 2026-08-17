import AppKit
import KeyboardShortcuts
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var refreshCoordinator: RefreshCoordinator?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("AppDelegate.didFinishLaunching")
        applyActivationPolicy()

        // Deferred so shortcut registration can never block app startup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.setupGlobalShortcut()
        }

        if let state = AppState.current {
            Log.info("AppDelegate: state ready")
            refreshCoordinator = RefreshCoordinator(state: state)
            refreshCoordinator?.start()
            state.refreshCoordinator = refreshCoordinator

            let env = ProcessInfo.processInfo.environment
            if env["APIMETER_OPEN_DASHBOARD"] == "1" {
                // Verification aid: present the dashboard (or mini) at launch.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    state.floatingPanelController?.show(mode: env["APIMETER_MINI"] == "1" ? .mini : .full)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else if AppSettings.shared.openDashboardAtLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    state.floatingPanelController?.show()
                }
            }
        } else {
            Log.error("AppDelegate: AppState.current is nil")
        }
    }

    /// Dock icon toggle (spec 51) - updates the activation policy immediately.
    @MainActor
    func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = AppSettings.shared.showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }

    private func setupGlobalShortcut() {
        Log.info("AppDelegate: registering global shortcut")
        KeyboardShortcuts.onKeyUp(for: .toggleDashboard) {
            Task { @MainActor in
                AppState.current?.toggleDashboard()
            }
        }
    }
}
