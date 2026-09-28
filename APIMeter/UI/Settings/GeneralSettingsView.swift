import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// General settings (spec 57): launch at login, dashboard visibility,
/// dock icon, global shortcuts, desktop widget panel.
struct GeneralSettingsView: View {
    @Bindable var state: AppState
    @State private var loginItemStatus = ""

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { state.environment.settings.launchAtLogin },
                    set: { enabled in setLaunchAtLogin(enabled) }
                ))
                Text(loginItemStatus).font(.caption).foregroundStyle(.secondary)
            }
            Section("Dashboard") {
                Toggle("Show Dashboard", isOn: Binding(
                    get: { state.floatingPanelController?.isVisible ?? false },
                    set: { visible in
                        if visible {
                            state.floatingPanelController?.show()
                        } else {
                            state.floatingPanelController?.hide()
                        }
                    }
                ))
                Toggle("Open Dashboard at Launch", isOn: Binding(
                    get: { state.environment.settings.openDashboardAtLaunch },
                    set: { state.environment.settings.openDashboardAtLaunch = $0 }
                ))
                Text("The floating dashboard's pin state (always on top) is remembered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Dock") {
                Toggle("Show Dock Icon", isOn: Binding(
                    get: { state.environment.settings.showDockIcon },
                    set: { newValue in
                        state.environment.settings.showDockIcon = newValue
                        (NSApp.delegate as? AppDelegate)?.applyActivationPolicy()
                    }
                ))
            }
            Section("Global Shortcut") {
                HStack {
                    Text("Toggle Dashboard")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleDashboard)
                }
                HStack {
                    Text("Toggle Desktop Widgets")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleWidgets)
                }
                Text("Dashboard: Option + Space. Widgets: Option + W. Both are changeable here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Desktop Widgets") {
                Toggle("Show Desktop Widgets", isOn: Binding(
                    get: { state.environment.settings.showDesktopWidgets },
                    set: { enabled in
                        state.environment.settings.showDesktopWidgets = enabled
                        if enabled {
                            state.widgetPanelController?.show()
                        } else {
                            state.widgetPanelController?.hide()
                        }
                    }
                ))
                Text("Floating cards at desktop level: ZCode, Kimi, Qoder and Codex quota windows plus the DeepSeek balance. Provider credentials are configured in Settings > Coding Plans. The macOS system widgets (WidgetKit) are managed by macOS: long-press the desktop or Notification Center to add them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .task {
            updateLoginItemStatus()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            state.environment.settings.launchAtLogin = enabled
        } catch {
            loginItemStatus = "Could not change login item: " + error.localizedDescription + " (the app must be moved to /Applications for reliable launch at login)"
        }
        updateLoginItemStatus()
    }

    private func updateLoginItemStatus() {
        switch SMAppService.mainApp.status {
        case .enabled: loginItemStatus = "Enabled"
        case .requiresApproval: loginItemStatus = "Requires approval in System Settings"
        case .notFound: loginItemStatus = "Not registered"
        @unknown default: loginItemStatus = ""
        }
    }
}
