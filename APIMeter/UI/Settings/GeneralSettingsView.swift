import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// General settings (spec 57): launch at login, dock icon, shortcut,
/// open dashboard at launch, window restore.
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
                Toggle("Open Dashboard at Launch", isOn: Binding(
                    get: { state.environment.settings.openDashboardAtLaunch },
                    set: { state.environment.settings.openDashboardAtLaunch = $0 }
                ))
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
                Text("Default: Option + Space. The shortcut shows or hides the dashboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Windows") {
                Toggle("Restore Window State", isOn: Binding(
                    get: { state.environment.settings.restoreWindowState },
                    set: { state.environment.settings.restoreWindowState = $0 }
                ))
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
