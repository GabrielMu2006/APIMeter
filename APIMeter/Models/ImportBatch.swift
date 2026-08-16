import Foundation

/// One successfully imported file (spec §16 file-level dedup).
public struct ImportBatch: Identifiable, Equatable, Sendable {
    public var id: Int64?
    public let fileHash: String
    public let filename: String?
    public let month: String?
    public let importedAt: Date
    public let rowCount: Int

    public init(id: Int64? = nil, fileHash: String, filename: String?, month: String?, importedAt: Date, rowCount: Int) {
        self.id = id
        self.fileHash = fileHash
        self.filename = filename
        self.month = month
        self.importedAt = importedAt
        self.rowCount = rowCount
    }
}
