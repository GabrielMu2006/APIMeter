import SwiftUI

/// Multi-select API key filter (spec 38) with Select All / Clear.
struct APIKeyFilter: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Menu {
            Button("Select All") { viewModel.selectAllKeys() }
            Button("Clear") { viewModel.clearKeySelection() }
            Divider()
            if viewModel.apiKeys.isEmpty {
                Text("No keys found").foregroundStyle(.secondary)
            }
            ForEach(viewModel.apiKeys) { key in
                Button {
                    toggle(key.fingerprint)
                } label: {
                    if viewModel.selectedFingerprints.contains(key.fingerprint) {
                        Label(key.bestDisplayName, systemImage: "checkmark")
                    } else {
                        Label(key.bestDisplayName, systemImage: "circle")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "key")
                Text(labelText)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onChange(of: viewModel.selectedFingerprints) {
            Task { await viewModel.reload() }
        }
    }

    private var labelText: String {
        let total = viewModel.apiKeys.count
        let selected = viewModel.selectedFingerprints.count
        if selected == 0 { return "All Keys" }
        if selected == total && total > 0 { return "All Keys" }
        return String(selected) + " of " + String(total) + " Keys"
    }

    private func toggle(_ fingerprint: String) {
        if viewModel.selectedFingerprints.contains(fingerprint) {
            viewModel.selectedFingerprints.remove(fingerprint)
        } else {
            viewModel.selectedFingerprints.insert(fingerprint)
        }
    }
}
