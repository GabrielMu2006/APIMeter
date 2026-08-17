import Foundation

public enum ImportError: Error, LocalizedError {
    case unsupportedSchema(details: String)
    case duplicateFile(filename: String)
    case emptyFile
    case unreadableFile(String)
    case zipExtractionFailed(String)
    case tooManyFiles(Int)
    case fileTooLarge(Int64)
    case invalidDay(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let details): return "This DeepSeek usage file uses an unsupported format. The file was not imported. Details: " + details
        case .duplicateFile(let filename): return "This usage file has already been imported: " + filename
        case .emptyFile: return "The file contains no usable rows."
        case .unreadableFile(let reason): return "Could not read the file: " + reason
        case .zipExtractionFailed(let reason): return "ZIP extraction failed: " + reason
        case .tooManyFiles(let count): return "The ZIP contains too many CSV files (" + String(count) + ")."
        case .fileTooLarge(let bytes): return "The file is too large (" + String(bytes) + " bytes)."
        case .invalidDay(let value): return "Invalid date value in file: " + value
        }
    }
}

public struct ImportResult: Equatable, Sendable {
    public let fileHash: String
    public let filesImported: Int
    public let rowsInFile: Int
    public let inserted: Int
    public let ignoredDuplicates: Int
}

/// Converts parsed CSV rows into the internal standard UsageRecord model.
/// A mapper only exists AFTER the real file schema has been analyzed and
/// documented - we never guess external schemas (spec 14/117).
public protocol CSVMapper: Sendable {
    /// Registered identifier, e.g. "deepseek-official-v1"
    var schemaID: String { get }
    func map(rows: [[String]]) throws -> CSVMapping
}

/// Full import pipeline (spec 13):
/// File -> Detect Type -> ZIP Extract -> CSV Parser -> Mapper -> Dedup -> SQLite -> Aggregation.
public struct UsageImportService: Sendable {
    public static let maxFileBytes: Int64 = 100 * 1024 * 1024

    private let repository: UsageRepository

    public init(repository: UsageRepository) {
        self.repository = repository
    }

    public func importFile(at url: URL, mapper: CSVMapper) async throws -> ImportResult {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw ImportError.emptyFile }
        guard size <= Self.maxFileBytes else { throw ImportError.fileTooLarge(size) }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadableFile(error.localizedDescription)
        }
        let fileHash = ImportDeduplicator.fileHash(data)

        // File-level dedup (spec 16).
        guard try repository.importBatchExists(fileHash: fileHash) == false else {
            throw ImportError.duplicateFile(filename: url.lastPathComponent)
        }

        // Detect ZIP by magic bytes, not by extension.
        let isZip = data.starts(with: [0x50, 0x4B, 0x03, 0x04])
        if isZip {
            let files = try ZIPExtractor.extract(zipURL: url)
            guard !files.isEmpty else { throw ImportError.emptyFile }
            var total = ImportResult(fileHash: fileHash, filesImported: files.count, rowsInFile: 0, inserted: 0, ignoredDuplicates: 0)
            for file in files {
                let part = try await importCSV(at: file, mapper: mapper)
                total = ImportResult(fileHash: total.fileHash, filesImported: total.filesImported, rowsInFile: total.rowsInFile + part.rowsInFile, inserted: total.inserted + part.inserted, ignoredDuplicates: total.ignoredDuplicates + part.ignoredDuplicates)
            }
            return total
        }
        return try await importCSV(at: url, mapper: mapper)
    }

    /// Imports one CSV file (also used for each file inside a ZIP).
    public func importCSV(at url: URL, mapper: CSVMapper) async throws -> ImportResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadableFile(error.localizedDescription)
        }
        let fileHash = ImportDeduplicator.fileHash(data)
        guard try repository.importBatchExists(fileHash: fileHash) == false else {
            throw ImportError.duplicateFile(filename: url.lastPathComponent)
        }
        let rows = try CSVParser.parse(data: data)
        guard rows.count > 1 else { throw ImportError.emptyFile }

        let mapping = try mapper.map(rows: rows)
        guard !mapping.records.isEmpty else {
            throw ImportError.unsupportedSchema(details: "Mapper '" + mapper.schemaID + "' produced no records")
        }

        let stats = try repository.upsert(mapping.records)
        // Cross-check derived per-key costs against billing totals (idempotent,
        // order-independent - safe to run after every file import).
        let reconciled = try repository.reconcileDerivedCosts()
        // Official key names from the export become the api_keys display names.
        for (fingerprint, officialName) in mapping.keyNames {
            try repository.setOfficialName(officialName, fingerprint: fingerprint)
        }
        // Seed official price rules (never hardcoded prices, spec 28-30).
        var rulesSeeded = 0
        for rule in mapping.priceRules {
            if try repository.hasPriceRule(rule) == false {
                try repository.upsertPriceRules([rule])
                rulesSeeded += 1
            }
        }
        let month = Self.monthOf(mapping.records)
        try repository.recordImportBatch(ImportBatch(
            fileHash: fileHash,
            filename: url.lastPathComponent,
            month: month,
            importedAt: Date(),
            rowCount: rows.count - 1
        ))
        Log.info("Import " + url.lastPathComponent + ": " + String(stats.inserted) + " inserted, " + String(stats.ignoredDuplicates) + " duplicate rows ignored, " + String(rulesSeeded) + " price rules seeded, " + String(reconciled) + " cost records reconciled")
        return ImportResult(
            fileHash: fileHash,
            filesImported: 1,
            rowsInFile: rows.count - 1,
            inserted: stats.inserted,
            ignoredDuplicates: stats.ignoredDuplicates
        )
    }

    static func monthOf(_ records: [UsageRecord]) -> String? {
        guard let minDay = records.map({ $0.day.value }).min() else { return nil }
        return String(minDay.prefix(7))
    }
}
