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

            Section("DeepSeekSync Setup") {
                if let installer = state.syncInstaller {
                    switch installer.phase {
                    case .idle:
                        if installer.isConfigured {
                            Label("已安装", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                        } else {
                            Button("自动下载并安装 DeepSeekSync") {
                                Task { await installer.install() }
                            }
                            Text("首次约 450MB（Node + Chromium，一次性）；安装后会自动打开 DeepSeek 登录窗口。")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    case .downloading(let fraction):
                        LabeledContent("下载模块", value: String(Int(fraction * 100)) + "%")
                        ProgressView(value: fraction)
                    case .extracting:
                        LabeledContent("状态", value: "解压模块...")
                        ProgressView()
                    case .settingUp:
                        LabeledContent("状态", value: "安装运行时（Node + Chromium ~450MB）...")
                        ProgressView()
                    case .openingLogin:
                        LabeledContent("状态", value: "已打开 DeepSeek 登录窗口")
                        ProgressView()
                        Text("请在弹出的浏览器中完成登录；完成后此页会自动更新。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    case .done:
                        Label("安装完成，请在登录窗口中完成 DeepSeek 登录", systemImage: "checkmark.circle")
                    case .cancelled:
                        Button("重新自动安装") { Task { await installer.install() } }
                    case .failed(let message):
                        Text("安装失败：" + message)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("重试") { Task { await installer.install() } }
                    }
                    if !installer.logTail.isEmpty {
                        ScrollView {
                            Text(installer.logTail)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
                    }
                    if installer.isActive {
                        Button("取消", role: .destructive) { installer.cancel() }
                    }
                } else {
                    Text("自动安装不可用。请手动填写下方路径。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Daily Export Sync") {
                LabeledContent("Status", value: syncStatusText)
                TextField("DeepSeekSync path (empty = disabled)", text: Binding(
                    get: { state.environment.settings.syncToolPath ?? "" },
                    set: { state.environment.settings.syncToolPath = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
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
