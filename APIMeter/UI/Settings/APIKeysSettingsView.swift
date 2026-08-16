import SwiftUI

/// Local key aliases (spec 39). Renaming never touches DeepSeek servers.
struct APIKeysSettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keys found in usage data. The local alias only changes how API Meter displays the key.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.settingsViewModel.apiKeys.isEmpty {
                Text("No API keys yet - import a usage export first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            } else {
                List(state.settingsViewModel.apiKeys) { key in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.officialName ?? "Unknown key")
                                .font(.callout)
                            Text("••••" + KeyFingerprint.displayPrefix(key.fingerprint, length: 4))
                                .font(.caption2)
                                .monospaced()
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        TextField("Alias", text: Binding(
                            get: { key.displayName ?? "" },
                            set: { newValue in
                                Task { await state.settingsViewModel.renameKey(key, to: newValue) }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
    }
}
