import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("API Meter")
                .font(.title2.weight(.semibold))
            Text("Version 1.1.0")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Native macOS usage dashboard for DeepSeek.\nBalance from the official API, history from official usage exports,\nrealtime estimates from the optional local gateway.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("All data stays on this Mac. API keys live in the Keychain only.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
