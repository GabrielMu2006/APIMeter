import Foundation
import GRDB

public struct UsageUpsertStats: Equatable, Sendable {
    public let inserted: Int
    public let ignoredDuplicates: Int
}

/// The single storage facade UI may talk to (spec 78).
/// UI never learns whether data came from CSV, gateway or SQLite.
public struct UsageRepository: Sendable {
    private let database: DatabaseManager

    public init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - API keys

    public func fetchAPIKeys() throws -> [APIKey] {
        try database.dbQueue.read { db in
            try APIKeyRow.order(Column("id")).fetchAll(db).map { $0.model }
        }
    }

    public func setDisplayName(_ name: String?, fingerprint: String) throws {
        try database.dbQueue.write { db in
            try APIKeyRow
                .filter(Column("fingerprint") == fingerprint)
                .updateAll(db, Column("display_name").set(to: name))
        }
    }

    public func setOfficialName(_ name: String, fingerprint: String) throws {
        try database.dbQueue.write { db in
            let row = APIKeyRow.filter(Column("fingerprint") == fingerprint)
            if try row.isEmpty(db) {
                var new = APIKeyRow(id: nil, fingerprint: fingerprint, displayName: nil, officialName: name, enabled: true, createdAt: ISO8601.string(Date()))
                try new.insert(db)
            } else {
                try row.updateAll(db, Column("official_name").set(to: name))
            }
        }
    }

    // MARK: - Usage records

    /// Inserts records; rows whose source_row_hash already exists are ignored (spec 17).
    public func upsert(_ records: [UsageRecord]) throws -> UsageUpsertStats {
        try database.dbQueue.write { db in
            var inserted = 0
            var ignored = 0
            for record in records {
                if try Self.insert(record, in: db) { inserted += 1 } else { ignored += 1 }
            }
            return UsageUpsertStats(inserted: inserted, ignoredDuplicates: ignored)
        }
    }

    private static func insert(_ record: UsageRecord, in db: Database) throws -> Bool {
        var apiKeyId: Int64?
        if let fingerprint = record.apiKeyFingerprint {
            if let existing = try APIKeyRow.filter(Column("fingerprint") == fingerprint).fetchOne(db) {
                apiKeyId = existing.id
            } else {
                var row = APIKeyRow(id: nil, fingerprint: fingerprint, displayName: nil, officialName: nil, enabled: true, createdAt: ISO8601.string(Date()))
                try row.insert(db)
                apiKeyId = row.id
            }
        }
        let hash = ImportDeduplicator.rowHash(record)
        try db.execute(sql: """
            INSERT OR IGNORE INTO usage_records
            (timestamp, day, api_key_id, model, request_count, cache_hit_tokens, cache_miss_tokens,
             input_tokens, output_tokens, total_tokens, amount, currency, source, verification_state,
             source_row_hash, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                record.timestamp.map(ISO8601.string),
                record.day.value,
                apiKeyId,
                record.model,
                record.requestCount,
                record.cacheHitTokens,
                record.cacheMissTokens,
                record.inputTokens,
                record.outputTokens,
                record.totalTokens,
                record.amount.map(DecimalStorage.string),
                record.currency,
                record.source.rawValue,
                record.verification.rawValue,
                hash,
                ISO8601.string(Date()),
            ])
        return db.changesCount > 0
    }

    /// REPLACE semantics for official imports: DeepSeek day buckets are
    /// cumulative snapshots - a newer export supersedes earlier totals for
    /// the same (day, model, api key). Old official rows for each incoming
    /// group are deleted first, so re-imports never accumulate.
    public func replaceOfficialRecords(_ records: [UsageRecord]) throws -> UsageUpsertStats {
        try database.dbQueue.write { db in
            var inserted = 0
            var ignored = 0
            var handledKeys = Set<String>()
            for record in records {
                let fingerprintKey = record.apiKeyFingerprint ?? ""
                let groupKey = record.day.value + "|" + (record.model ?? "") + "|" + fingerprintKey
                if !handledKeys.contains(groupKey) {
                    handledKeys.insert(groupKey)
                    if record.apiKeyFingerprint == nil {
                        try db.execute(sql: """
                            DELETE FROM usage_records
                            WHERE source = ? AND day = ? AND model IS ? AND api_key_id IS NULL
                            """, arguments: [UsageSource.officialCSV.rawValue, record.day.value, record.model])
                    } else {
                        try db.execute(sql: """
                            DELETE FROM usage_records
                            WHERE source = ? AND day = ? AND model IS ?
                              AND api_key_id IN (SELECT id FROM api_keys WHERE fingerprint = ?)
                            """, arguments: [UsageSource.officialCSV.rawValue, record.day.value, record.model, record.apiKeyFingerprint!])
                    }
                }
                if try Self.insert(record, in: db) { inserted += 1 } else { ignored += 1 }
            }
            return UsageUpsertStats(inserted: inserted, ignoredDuplicates: ignored)
        }
    }

    // MARK: - Queries

    /// Daily aggregation for [start, end], optionally filtered to API key fingerprints.
    public func dailyUsage(from start: LocalDay, to end: LocalDay, fingerprints: Set<String>? = nil) throws -> [DailyUsage] {
        let records = try recordsInRange(from: start, to: end, fingerprints: fingerprints)
        return UsageAggregator.daily(from: records)
    }

    public func summary(from start: LocalDay, to end: LocalDay, fingerprints: Set<String>? = nil) throws -> UsageSummary {
        let records = try recordsInRange(from: start, to: end, fingerprints: fingerprints)
        return UsageAggregator.summarize(records)
    }

    public func recordsInRange(from start: LocalDay, to end: LocalDay, fingerprints: Set<String>? = nil) throws -> [UsageRecord] {
        try database.dbQueue.read { db in
            let rows = try UsageRow
                .filter(Column("day") >= start.value && Column("day") <= end.value)
                .order(Column("day"), Column("id"))
                .fetchAll(db)
            let fingerprintById = try Self.fingerprintMap(db)
            let filtered: [UsageRow]
            if let fingerprints {
                filtered = rows.filter { row in
                    guard let id = row.apiKeyId, let fp = fingerprintById[id] else { return false }
                    return fingerprints.contains(fp)
                }
            } else {
                filtered = rows
            }
            return filtered.map { $0.usageRecord(fingerprint: $0.apiKeyId.flatMap { fingerprintById[$0] }) }
        }
    }

    public func recordCount() throws -> Int {
        try database.dbQueue.read { try UsageRow.fetchCount($0) }
    }

    private static func fingerprintMap(_ db: Database) throws -> [Int64: String] {
        let keys = try APIKeyRow.fetchAll(db)
        var map: [Int64: String] = [:]
        for key in keys { if let id = key.id { map[id] = key.fingerprint } }
        return map
    }

    // MARK: - Balance snapshots

    public func saveBalanceSnapshot(_ balance: Balance) throws {
        try database.dbQueue.write { db in
            let now = ISO8601.string(balance.fetchedAt)
            for info in balance.balanceInfos {
                var row = BalanceSnapshotRow(
                    id: nil, timestamp: now, isAvailable: balance.isAvailable,
                    total: DecimalStorage.string(info.totalBalance),
                    granted: DecimalStorage.string(info.grantedBalance),
                    toppedUp: DecimalStorage.string(info.toppedUpBalance),
                    currency: info.currency
                )
                try row.insert(db)
            }
        }
    }

    /// Latest snapshot, reconstructed into a Balance (keeps last successful data, spec 81).
    public func latestBalanceSnapshot() throws -> Balance? {
        try database.dbQueue.read { db -> Balance? in
            guard let ts = try String.fetchOne(db, sql: "SELECT MAX(timestamp) FROM balance_snapshots") else { return nil }
            let rows = try BalanceSnapshotRow.filter(Column("timestamp") == ts).fetchAll(db)
            guard !rows.isEmpty else { return nil }
            let infos = rows.map { row in
                BalanceInfo(
                    currency: row.currency,
                    totalBalance: DecimalStorage.decimal(row.total) ?? Decimal(0),
                    grantedBalance: row.granted.flatMap { DecimalStorage.decimal($0) } ?? Decimal(0),
                    toppedUpBalance: row.toppedUp.flatMap { DecimalStorage.decimal($0) } ?? Decimal(0)
                )
            }
            let available = rows.first?.isAvailable ?? true
            return Balance(isAvailable: available, balanceInfos: infos, fetchedAt: ISO8601.date(ts) ?? Date())
        }
    }

    // MARK: - Import batches

    public func importBatchExists(fileHash: String) throws -> Bool {
        try database.dbQueue.read { db in
            try ImportBatchRow.filter(Column("file_hash") == fileHash).isEmpty(db) == false
        }
    }

    /// Deletes all import metadata (used by the rebuild path so the same
    /// export file can be re-imported after usage rows were cleared).
    @discardableResult
    public func clearImportBatches() throws -> Int {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM import_batches")
            return db.changesCount
        }
    }

    public func recordImportBatch(_ batch: ImportBatch) throws {
        try database.dbQueue.write { db in
            var row = ImportBatchRow(
                id: nil, fileHash: batch.fileHash, filename: batch.filename, month: batch.month,
                importedAt: ISO8601.string(batch.importedAt), rowCount: batch.rowCount
            )
            try row.insert(db)
        }
    }

    public func fetchImportBatches() throws -> [ImportBatch] {
        try database.dbQueue.read { db in
            try ImportBatchRow.order(Column("id").desc).fetchAll(db).map { $0.model }
        }
    }

    // MARK: - Price rules

    public func upsertPriceRules(_ rules: [PriceRule]) throws {
        try database.dbQueue.write { db in
            for rule in rules {
                var row = PriceRuleRow(
                    id: nil, provider: rule.provider, model: rule.model,
                    effectiveFrom: ISO8601.string(rule.effectiveFrom),
                    effectiveTo: rule.effectiveTo.map(ISO8601.string),
                    period: rule.period?.rawValue,
                    cacheHitPrice: rule.cacheHitPrice.map(DecimalStorage.string),
                    cacheMissPrice: rule.cacheMissPrice.map(DecimalStorage.string),
                    outputPrice: rule.outputPrice.map(DecimalStorage.string),
                    currency: rule.currency
                )
                try row.insert(db)
            }
        }
    }

    /// Exact-match existence check so re-imports do not duplicate rules.
    public func hasPriceRule(_ rule: PriceRule) throws -> Bool {
        let existing = try fetchPriceRules(provider: rule.provider)
        return existing.contains { candidate in
            candidate.model == rule.model
                && candidate.effectiveFrom == rule.effectiveFrom
                && candidate.effectiveTo == rule.effectiveTo
                && candidate.cacheHitPrice == rule.cacheHitPrice
                && candidate.cacheMissPrice == rule.cacheMissPrice
                && candidate.outputPrice == rule.outputPrice
                && candidate.currency == rule.currency
        }
    }

    public func fetchPriceRules(provider: String? = nil) throws -> [PriceRule] {
        try database.dbQueue.read { db in
            var request = PriceRuleRow.all()
            if let provider {
                request = request.filter(Column("provider") == provider)
            }
            return try request.order(Column("model"), Column("effective_from")).fetchAll(db).compactMap { $0.modelRule }
        }
    }

    // MARK: - Balance-derived today estimate

    /// Estimates today's spend from balance snapshots (user's method):
    /// walks today's snapshots from the last pre-today baseline and sums
    /// only DECREASES; increases are treated as top-ups and ignored.
    /// Returns nil when there is no pre-today snapshot to anchor against.
    /// This is an ESTIMATE - official export data overrides it when present.
    public func estimatedTodaySpend(now: Date = Date()) throws -> Decimal? {
        try database.dbQueue.read { db in
            let rows = try BalanceSnapshotRow
                .filter(Column("currency") == "CNY")
                .order(Column("timestamp"))
                .fetchAll(db)
            guard !rows.isEmpty else { return nil }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            let todayStart = calendar.startOfDay(for: now)

            let parsed: [(timestamp: Date, total: Decimal)] = rows.compactMap { row in
                guard let date = ISO8601.date(row.timestamp) else { return nil }
                return (date, DecimalStorage.decimal(row.total) ?? 0)
            }
            guard let baselineIndex = parsed.lastIndex(where: { $0.timestamp < todayStart }) else {
                return nil
            }
            // Safety rule: the baseline must be recent (within 24 h before
            // midnight). An older baseline would mix several days of spending
            // into the estimate.
            let baseline = parsed[baselineIndex]
            if baseline.timestamp < todayStart.addingTimeInterval(-24 * 3600) {
                return nil
            }
            var previous = parsed[baselineIndex].total
            var spend = Decimal.zero
            var anyToday = false
            for entry in parsed.dropFirst(baselineIndex + 1) where entry.timestamp >= todayStart {
                anyToday = true
                let delta = previous - entry.total
                if delta > 0 { spend += delta }
                previous = entry.total
            }
            return anyToday ? spend : nil
        }
    }

    // MARK: - Derived cost reconciliation

    /// Cross-checks DERIVED per-key costs (price * amount from the amount file)
    /// against BILLING totals (cost file) per (day, model).
    /// - exact match: currency is filled from the billing row, stays official.
    /// - mismatch (beyond tolerance): keyed rows are downgraded to estimated
    ///   (honest, spec 127 - accuracy over convenience).
    /// Idempotent and order-independent: run after every import.
    @discardableResult
    public func reconcileDerivedCosts() throws -> Int {
        try database.dbQueue.write { db in
            let keyedRows = try UsageRow
                .filter(Column("source") == UsageSource.officialCSV.rawValue)
                .filter(Column("api_key_id") != nil)
                .filter(Column("amount") != nil)
                .fetchAll(db)
            let billingRows = try UsageRow
                .filter(Column("source") == UsageSource.officialCSV.rawValue)
                .filter(Column("api_key_id") == nil)
                .filter(Column("amount") != nil)
                .fetchAll(db)

            // Billing totals per (day, model): sum + currency.
            var billing: [String: (total: Decimal, currency: String)] = [:]
            for row in billingRows {
                let key = row.day + "|" + (row.model ?? "")
                let amount = row.amount.flatMap(DecimalStorage.decimal) ?? 0
                var entry = billing[key] ?? (total: 0, currency: "")
                entry.total += amount
                if entry.currency.isEmpty { entry.currency = row.currency ?? "" }
                billing[key] = entry
            }

            // Group keyed rows per (day, model).
            var groups: [String: [UsageRow]] = [:]
            for row in keyedRows {
                let key = row.day + "|" + (row.model ?? "")
                groups[key, default: []].append(row)
            }

            var updated = 0
            for (key, rows) in groups {
                guard let bill = billing[key] else { continue }
                let derivedTotal = rows.reduce(Decimal.zero) { partial, row in
                    partial + (row.amount.flatMap(DecimalStorage.decimal) ?? 0)
                }
                let diff = (bill.total - derivedTotal)
                let magnitude = diff < 0 ? -diff : diff
                let matches = magnitude < Decimal(string: "0.000001")!
                for row in rows {
                    var assignments: [ColumnAssignment] = []
                    if matches {
                        if !bill.currency.isEmpty {
                            assignments.append(Column("currency").set(to: bill.currency))
                        }
                    } else {
                        assignments.append(Column("verification_state").set(to: VerificationState.estimated.rawValue))
                    }
                    if !assignments.isEmpty {
                        try UsageRow.filter(Column("id") == row.id).updateAll(db, assignments)
                        updated += 1
                    }
                }
            }
            return updated
        }
    }

    // MARK: - Clear

    /// Deletes all usage rows but KEEPS import_batches metadata (spec 84),
    /// so previously imported files stay deduplicated.
    @discardableResult
    public func clearUsageRecords() throws -> Int {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM usage_records")
            return db.changesCount
        }
    }

    // MARK: - Retention

    /// Deletes usage older than the configured retention. Import metadata is
    /// intentionally kept (spec 84) so re-imports stay deduplicated.
    @discardableResult
    public func applyRetention(_ retention: HistoryRetention, now: LocalDay = LocalDay(date: Date())) throws -> Int {
        guard let days = retention.days else { return 0 }  // forever
        let cutoff = now.adding(days: -days)
        return try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM usage_records WHERE day < ?", arguments: [cutoff.value])
            return db.changesCount
        }
    }
}
