import Foundation

/// One CSV file parsed and mapped, ready for a single-transaction import.
public struct PreparedFile: Sendable {
    public let fileHash: String
    public let filename: String?
    public let records: [UsageRecord]
    public let keyNames: [(fingerprint: String, officialName: String)]
    public let priceRules: [PriceRule]
    public let month: String?
    public let rowCount: Int

    public init(fileHash: String, filename: String?, records: [UsageRecord], keyNames: [(fingerprint: String, officialName: String)], priceRules: [PriceRule], month: String?, rowCount: Int) {
        self.fileHash = fileHash
        self.filename = filename
        self.records = records
        self.keyNames = keyNames
        self.priceRules = priceRules
        self.month = month
        self.rowCount = rowCount
    }
}
