import SwiftUI

/// Settings container (spec 56). Phase B ships DeepSeek + API Keys + Data.
struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        TabView {
            DeepSeekSettingsView(state: state)
                .tabItem { Label("DeepSeek", systemImage: "wave.3.right") }
            APIKeysSettingsView(state: state)
                .tabItem { Label("API Keys", systemImage: "key") }
            DataSettingsView(state: state)
                .tabItem { Label("Data", systemImage: "internaldrive") }
        }
        .frame(width: 580, height: 440)
        .task {
            await state.settingsViewModel.reload()
        }
    }
}
