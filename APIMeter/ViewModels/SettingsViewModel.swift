import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Settings actions: API key management, import, data maintenance.
@MainActor
@Observable
public final class SettingsViewModel {
    public var apiKeyInput = ""
    public var statusMessage: String?
    public var importMessage: String?
    public var isImporting = false
    public var importedBatches: [ImportBatch] = []
    public var apiKeys: [APIKey] = []
    public var databaseSizeBytes: Int64 = 0
    public var balance: Balance?

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func reload() async {
        apiKeys = (try? environment.repository.fetchAPIKeys()) ?? []
        importedBatches = (try? environment.repository.fetchImportBatches()) ?? []
        databaseSizeBytes = environment.databaseSizeBytes
    }

    public func saveAPIKey() async {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter a DeepSeek API key first."
            return
        }
        do {
            let fingerprint = try environment.keychain.saveAPIKey(trimmed)
            apiKeyInput = ""
            statusMessage = "Key saved to Keychain. Fingerprint " + KeyFingerprint.displayPrefix(fingerprint, length: 8) + "..."
        } catch {
            statusMessage = "Failed to save key: " + error.localizedDescription
        }
    }

    public func testConnection() async {
        let fingerprints = (try? environment.keychain.listFingerprints()) ?? []
        guard let fingerprint = fingerprints.first else {
            statusMessage = "Save an API key first."
            return
        }
        do {
            let fresh = try await environment.balanceProvider(fingerprint).fetchBalance()
            balance = fresh
            try environment.repository.saveBalanceSnapshot(fresh)
            statusMessage = "Connection OK."
        } catch {
            statusMessage = "Connection failed: " + error.localizedDescription
        }
    }

    public func removeStoredKey() async {
        let fingerprints = (try? environment.keychain.listFingerprints()) ?? []
        for fingerprint in fingerprints {
            try? environment.keychain.deleteAPIKey(fingerprint: fingerprint)
        }
        statusMessage = "Stored key removed from Keychain."
    }

    public func renameKey(_ key: APIKey, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try? environment.repository.setDisplayName(trimmed.isEmpty ? nil : trimmed, fingerprint: key.fingerprint)
        await reload()
    }

    public func importFile(at url: URL) async {
        isImporting = true
        defer { isImporting = false }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try await environment.importService.importFile(at: url, mapper: DeepSeekOfficialCSVMapper())
            importMessage = "Imported " + String(result.inserted) + " records from " + String(result.filesImported) + " file(s). " + String(result.ignoredDuplicates) + " duplicate rows ignored."
            await reload()
        } catch {
            importMessage = error.localizedDescription
        }
    }

    /// Exports all local usage as CSV (spec 61).
    public func exportCSV() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "apimeter-export.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let records = try environment.repository.recordsInRange(
                from: LocalDay("2000-01-01")!,
                to: LocalDay("2100-01-01")!
            )
            let csv = UsageExportService.csvData(records: records)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            importMessage = "Exported " + String(records.count) + " rows."
        } catch {
            importMessage = "Export failed: " + error.localizedDescription
        }
    }

    public func clearUsageData() async {
        _ = try? environment.repository.clearUsageRecords()
        importMessage = "Local usage data cleared. Import history was kept."
        await reload()
    }
}
