import SwiftUI
import UniformTypeIdentifiers

/// Data management (spec 60): import, imported months, database size, clear.
/// Supports all three import ways from spec 12: ZIP drag, CSV drag, picker.
struct DataSettingsView: View {
    @Bindable var state: AppState
    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section("Import DeepSeek Usage") {
                HStack {
                    Button(state.settingsViewModel.isImporting ? "Importing..." : "Import Usage Export...") {
                        isFileImporterPresented = true
                    }
                    .disabled(state.settingsViewModel.isImporting)
                    Text("Drop a ZIP or CSV here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let message = state.settingsViewModel.importMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("Imported") ? Color.secondary : Color.red)
                        .textSelection(.enabled)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.zip, .commaSeparatedText, .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task {
                        await state.settingsViewModel.importFile(at: url)
                        await state.dashboardViewModel.reload()
                    }
                }
            }

            Section("Daily Export Sync") {
                LabeledContent("Status", value: syncStatusText)
                LabeledContent("Next run", value: state.syncScheduler?.nextRunText ?? "unknown")
                Text("The daily sync runs once a day at 00:30 (hidden browser) and imports the official export automatically. The Refresh button only updates the balance - it never triggers a sync.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("Local Data") {
                HStack {
                    Button("Export Local Data (CSV)...") {
                        Task { await state.settingsViewModel.exportCSV() }
                    }
                    if let message = state.settingsViewModel.importMessage, message.hasPrefix("Exported") {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Imported files", value: String(state.settingsViewModel.importedBatches.count))
                LabeledContent("Database size", value: ByteCountFormatter.string(fromByteCount: state.settingsViewModel.databaseSizeBytes, countStyle: .file))
                if !state.settingsViewModel.importedBatches.isEmpty {
                    ForEach(state.settingsViewModel.importedBatches.prefix(12)) { batch in
                        HStack {
                            Text(batch.filename ?? "?")
                                .lineLimit(1)
                            Spacer()
                            Text(String(batch.rowCount) + " rows")
                                .foregroundStyle(.secondary)
                            Text(batch.month ?? "")
                                .foregroundStyle(.tertiary)
                        }
                        .font(.caption)
                    }
                }
                Button("Clear Local Usage", role: .destructive) {
                    showClearConfirmation = true
                }
                Text("Import history is kept so previously imported files stay deduplicated.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .confirmationDialog(
            "Clear all local usage data? Import history is kept.",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Usage Data", role: .destructive) {
                Task {
                    await state.settingsViewModel.clearUsageData()
                    await state.dashboardViewModel.reload()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var syncStatusText: String {
        if let result = state.syncScheduler?.lastResult {
            return (result.ok ? "OK - " : "FAILED - ") + result.message
        }
        if let last = state.environment.settings.lastSyncResult {
            return last
        }
        if let day = state.environment.settings.lastSyncDay {
            return "Last sync: " + day
        }
        return "Not run yet"
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let ext = url.pathExtension.lowercased()
                guard ext == "zip" || ext == "csv" else { return }
                Task { @MainActor in
                    await state.settingsViewModel.importFile(at: url)
                    await state.dashboardViewModel.reload()
                }
            }
            return true
        }
        return false
    }
}
