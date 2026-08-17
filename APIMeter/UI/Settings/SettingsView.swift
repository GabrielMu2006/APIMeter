import SwiftUI

/// Settings container (spec 56): General, DeepSeek, API Keys, Usage,
/// Notifications, Gateway, Appearance, Data, About.
struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
            DeepSeekSettingsView(state: state)
                .tabItem { Label("DeepSeek", systemImage: "wave.3.right") }
            APIKeysSettingsView(state: state)
                .tabItem { Label("API Keys", systemImage: "key") }
            UsageSettingsView(state: state)
                .tabItem { Label("Usage", systemImage: "clock.arrow.circlepath") }
            NotificationSettingsView(state: state)
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            AppearanceSettingsView(state: state)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            DataSettingsView(state: state)
                .tabItem { Label("Data", systemImage: "internaldrive") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 480)
        .apiMeterAppearance(state.environment.settings.appearance)
        .task {
            await state.settingsViewModel.reload()
        }
    }
}
