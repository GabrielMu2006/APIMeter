import Foundation
import GRDB

/// GRDB row structs. All timestamps are UTC ISO8601 TEXT; amounts are decimal TEXT.
/// These are persistence-layer types — the domain models (UsageRecord etc.)
/// stay UI/persistence-agnostic.

struct APIKeyRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "api_keys"
    var id: Int64?
    var fingerprint: String
    var displayName: String?
    var officialName: String?
    var enabled: Bool
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, fingerprint, enabled
        case displayName = "display_name"
        case officialName = "official_name"
        case createdAt = "created_at"
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    var model: APIKey {
        APIKey(id: id, fingerprint: fingerprint, displayName: displayName, officialName: officialName, enabled: enabled, createdAt: ISO8601.date(createdAt) ?? .distantPast)
    }
}

struct UsageRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "usage_records"
    var id: Int64?
    var timestamp: String?
    var day: String
    var apiKeyId: Int64?
    var model: String?
    var requestCount: Int64?
    var cacheHitTokens: Int64?
    var cacheMissTokens: Int64?
    var inputTokens: Int64?
    var outputTokens: Int64?
    var totalTokens: Int64?
    var amount: String?
    var currency: String?
    var source: String
    var verificationState: String
    var sourceRowHash: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, timestamp, day, model, amount, currency, source
        case apiKeyId = "api_key_id"
        case requestCount = "request_count"
        case cacheHitTokens = "cache_hit_tokens"
        case cacheMissTokens = "cache_miss_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case verificationState = "verification_state"
        case sourceRowHash = "source_row_hash"
        case createdAt = "created_at"
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    func usageRecord(fingerprint: String?) -> UsageRecord {
        UsageRecord(
            id: id,
            timestamp: timestamp.flatMap(ISO8601.date),
            day: LocalDay(day)!,
            apiKeyFingerprint: fingerprint,
            model: model,
            requestCount: requestCount,
            cacheHitTokens: cacheHitTokens,
            cacheMissTokens: cacheMissTokens,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            amount: amount.flatMap(DecimalStorage.decimal),
            currency: currency,
            source: UsageSource(rawValue: source) ?? .localGateway,
            verification: VerificationState(rawValue: verificationState) ?? .estimated
        )
    }
}

struct BalanceSnapshotRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "balance_snapshots"
    var id: Int64?
    var timestamp: String
    var isAvailable: Bool
    var total: String
    var granted: String?
    var toppedUp: String?
    var currency: String

    enum CodingKeys: String, CodingKey {
        case id, timestamp, total, granted, currency
        case isAvailable = "is_available"
        case toppedUp = "topped_up"
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

struct ImportBatchRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "import_batches"
    var id: Int64?
    var fileHash: String
    var filename: String?
    var month: String?
    var importedAt: String
    var rowCount: Int

    enum CodingKeys: String, CodingKey {
        case id, filename, month
        case fileHash = "file_hash"
        case importedAt = "imported_at"
        case rowCount = "row_count"
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    var model: ImportBatch {
        ImportBatch(id: id, fileHash: fileHash, filename: filename, month: month, importedAt: ISO8601.date(importedAt) ?? .distantPast, rowCount: rowCount)
    }
}

struct PriceRuleRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "price_rules"
    var id: Int64?
    var provider: String
    var model: String
    var effectiveFrom: String
    var effectiveTo: String?
    var period: String?
    var cacheHitPrice: String?
    var cacheMissPrice: String?
    var outputPrice: String?
    var currency: String

    enum CodingKeys: String, CodingKey {
        case id, provider, model, period, currency
        case effectiveFrom = "effective_from"
        case effectiveTo = "effective_to"
        case cacheHitPrice = "cache_hit_price"
        case cacheMissPrice = "cache_miss_price"
        case outputPrice = "output_price"
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    var modelRule: PriceRule? {
        guard let from = ISO8601.date(effectiveFrom) else { return nil }
        return PriceRule(
            id: id,
            provider: provider,
            model: model,
            effectiveFrom: from,
            effectiveTo: effectiveTo.flatMap(ISO8601.date),
            period: period.flatMap(PricePeriod.init(rawValue:)),
            cacheHitPrice: cacheHitPrice.flatMap(DecimalStorage.decimal),
            cacheMissPrice: cacheMissPrice.flatMap(DecimalStorage.decimal),
            outputPrice: outputPrice.flatMap(DecimalStorage.decimal),
            currency: currency
        )
    }
}
