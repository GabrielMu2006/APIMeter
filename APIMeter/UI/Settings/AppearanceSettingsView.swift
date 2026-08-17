import SwiftUI

/// Appearance (spec 65): System / Light / Dark.
struct AppearanceSettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: Binding(
                    get: { state.environment.settings.appearance },
                    set: { state.environment.settings.appearance = $0 }
                )) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
                .pickerStyle(.radioGroup)
                Text("On macOS 26 the toolbar, filter controls and mini panel use Liquid Glass.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}
