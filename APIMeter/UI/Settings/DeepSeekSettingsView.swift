import SwiftUI

/// API key entry + connection status (spec 58). The raw key is never shown
/// after saving; only the Keychain fingerprint is displayed.
struct DeepSeekSettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("API Key") {
                if state.balanceViewModel.hasStoredKey == false {
                    SecureField("sk-...", text: $state.settingsViewModel.apiKeyInput)
                        .onSubmit {
                            Task { await state.settingsViewModel.saveAPIKey() }
                        }
                    Button("Save to Keychain") {
                        Task { await state.settingsViewModel.saveAPIKey() }
                    }
                    Text("The key is stored only in the macOS Keychain and is never written to the database or logs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Stored key") {
                        HStack(spacing: 6) {
                            Text("••••••••" + KeyFingerprint.displayPrefix(state.balanceViewModel.activeFingerprint ?? "", length: 4))
                                .monospaced()
                                .foregroundStyle(.secondary)
                            Button("Remove") {
                                Task { await state.settingsViewModel.removeStoredKey() }
                            }
                        }
                    }
                }
            }

            Section("Connection") {
                HStack {
                    Button("Test Connection") {
                        Task { await state.settingsViewModel.testConnection() }
                    }
                    if let balance = state.settingsViewModel.balance ?? state.balanceViewModel.balance {
                        ForEach(balance.balanceInfos, id: \.currency) { info in
                            Text(info.currency + " " + CurrencyFormatter.format(info.totalBalance, currency: info.currency))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Text("Last sync " + balance.fetchedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let message = state.settingsViewModel.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("Failed") || message.hasPrefix("Connection failed") ? .red : .secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}