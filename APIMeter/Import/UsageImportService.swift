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

/// Full import pipeline (spec 13). ZIP imports are ATOMIC: every contained
/// CSV is parsed/mapped first, then all files land in ONE database
/// transaction - a failure anywhere leaves the database untouched (review P1).
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

        let isZip = data.starts(with: [0x50, 0x4B, 0x03, 0x04])
        if isZip {
            return try await importArchive(data: data, url: url, mapper: mapper)
        }
        let prepared = try prepareCSV(data: data, filename: url.lastPathComponent, mapper: mapper)
        if try repository.importBatchExists(fileHash: prepared.fileHash) {
            throw ImportError.duplicateFile(filename: url.lastPathComponent)
        }
        let stats = try repository.importPreparedFiles([prepared], skipExisting: false)
        let reconciled = try repository.reconcileDerivedCosts()
        Log.info("Import " + url.lastPathComponent + ": " + String(stats.inserted) + " inserted, " + String(stats.ignoredDuplicates) + " ignored, " + String(reconciled) + " reconciled")
        return ImportResult(
            fileHash: prepared.fileHash,
            filesImported: 1,
            rowsInFile: prepared.rowCount,
            inserted: stats.inserted,
            ignoredDuplicates: stats.ignoredDuplicates
        )
    }

    // MARK: - ZIP (atomic)

    private func importArchive(data: Data, url: URL, mapper: CSVMapper) async throws -> ImportResult {
        let extraction = try ZIPExtractor.extract(zipURL: url)
        defer {
            // Always remove the scratch directory (review P1).
            try? FileManager.default.removeItem(at: extraction.tempDir)
        }
        guard !extraction.files.isEmpty else { throw ImportError.emptyFile }

        // Phase 1: parse + map every file BEFORE any write. Any failure here
        // leaves the database untouched.
        var preparedFiles: [PreparedFile] = []
        var alreadyImported = 0
        var totalRows = 0
        for file in extraction.files {
            let fileData = try Data(contentsOf: file)
            let prepared = try prepareCSV(data: fileData, filename: file.lastPathComponent, mapper: mapper)
            if try repository.importBatchExists(fileHash: prepared.fileHash) {
                alreadyImported += 1
                continue
            }
            totalRows += prepared.rowCount
            preparedFiles.append(prepared)
        }
        guard !preparedFiles.isEmpty else {
            throw ImportError.duplicateFile(filename: url.lastPathComponent)
        }

        // Phase 2: one transaction for every file (review P1).
        let stats = try repository.importPreparedFiles(preparedFiles, skipExisting: true)
        let reconciled = try repository.reconcileDerivedCosts()
        Log.info("Import ZIP " + url.lastPathComponent + ": " + String(stats.inserted) + " inserted, " + String(stats.ignoredDuplicates) + " ignored, " + String(alreadyImported) + " already imported, " + String(reconciled) + " reconciled")
        return ImportResult(
            fileHash: ImportDeduplicator.fileHash(data),
            filesImported: extraction.files.count,
            rowsInFile: totalRows,
            inserted: stats.inserted,
            ignoredDuplicates: stats.ignoredDuplicates + alreadyImported
        )
    }

    // MARK: - Preparation (pure IO + mapping, no writes)

    private func prepareCSV(data: Data, filename: String, mapper: CSVMapper) throws -> PreparedFile {
        let fileHash = ImportDeduplicator.fileHash(data)
        let rows = try CSVParser.parse(data: data)
        guard rows.count > 1 else { throw ImportError.emptyFile }
        let mapping = try mapper.map(rows: rows)
        guard !mapping.records.isEmpty else {
            throw ImportError.unsupportedSchema(details: "Mapper '" + mapper.schemaID + "' produced no records")
        }
        return PreparedFile(
            fileHash: fileHash,
            filename: filename,
            records: mapping.records,
            keyNames: mapping.keyNames,
            priceRules: mapping.priceRules,
            month: Self.monthOf(mapping.records),
            rowCount: rows.count - 1
        )
    }

    static func monthOf(_ records: [UsageRecord]) -> String? {
        guard let minDay = records.map({ $0.day.value }).min() else { return nil }
        return String(minDay.prefix(7))
    }
}
