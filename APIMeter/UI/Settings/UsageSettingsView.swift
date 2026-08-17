import SwiftUI

/// History retention (spec 59/84). Import metadata is always kept.
struct UsageSettingsView: View {
    @Bindable var state: AppState
    @State private var retentionMessage = ""

    var body: some View {
        Form {
            Section("History Retention") {
                Picker("Keep usage history", selection: Binding(
                    get: { state.environment.settings.retention },
                    set: { newValue in
                        state.environment.settings.retention = newValue
                        applyRetention(newValue)
                    }
                )) {
                    ForEach(HistoryRetention.allCases, id: \.self) { retention in
                        Text(retention.rawValue).tag(retention)
                    }
                }
                Text("Only affects local usage rows. Import history is kept so previously imported files stay deduplicated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(retentionMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func applyRetention(_ retention: HistoryRetention) {
        do {
            let deleted = try state.environment.repository.applyRetention(retention)
            retentionMessage = "Removed " + String(deleted) + " old usage rows."
            Task { await state.dashboardViewModel.reload() }
        } catch {
            retentionMessage = error.localizedDescription
        }
    }
}
