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

            // Daily export sync (00:30, catch-up on launch/wake).
            let syncScheduler = SyncScheduler(environment: state.environment)
            syncScheduler.start()
            state.syncScheduler = syncScheduler

            // One-click DeepSeekSync setup: prompt once when the module is
            // missing, offer to download + install + open the login window.
            let installer = DeepSeekSyncInstaller(settings: state.environment.settings)
            state.syncInstaller = installer
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.presentSyncSetupPromptIfNeeded(for: installer)
            }

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

    /// Launch-time dialog: offer one-click DeepSeekSync setup when the module
    /// is not configured yet. Any choice suppresses future prompts.
    @MainActor
    private func presentSyncSetupPromptIfNeeded(for installer: DeepSeekSyncInstaller) {
        guard !installer.isConfigured, !installer.isActive,
              !AppSettings.shared.dismissedSyncSetupPrompt else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "启用 DeepSeekSync 自动同步？"
        alert.informativeText = "DeepSeekSync 每天自动下载官方用量导出并导入（数据更准、按 Key 分成本）。"
            + "应用安装包不含该模块：首次需在线下载约 450MB（Node + Chromium，一次性）。"
            + "也可以稍后在 设置 → 数据 里手动配置。"
        alert.addButton(withTitle: "自动下载并安装（推荐）")
        alert.addButton(withTitle: "稍后手动配置")
        alert.addButton(withTitle: "暂不")
        AppSettings.shared.dismissedSyncSetupPrompt = true
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { @MainActor in await installer.install() }
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
