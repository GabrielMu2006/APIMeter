import Foundation
import GRDB

/// Migration v2 — quota snapshots for the ZCode/Zhipu Coding Plan monitor.
/// Same conventions as v1: UTC ISO8601 TEXT timestamps, exact decimal TEXT
/// amounts. One row per metering window per fetch.
///
/// Retention: unlike balance_snapshots, this table is pruned on write
/// (30 days) so it cannot grow unbounded.
enum V2QuotaSnapshots {
    static let retentionDays = 30

    static func createTables(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS quota_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                region TEXT NOT NULL,
                plan_level TEXT,
                window_kind TEXT NOT NULL,
                used_percent TEXT,
                used_value TEXT,
                total_value TEXT,
                remaining TEXT,
                resets_at TEXT,
                model_details TEXT,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_quota_snapshots_timestamp ON quota_snapshots(timestamp);
            CREATE INDEX IF NOT EXISTS idx_quota_snapshots_region ON quota_snapshots(region);
            """)
    }

    static func applyRetention(in db: Database, now: Date = Date()) throws {
        let cutoff = ISO8601.string(now.addingTimeInterval(-Double(retentionDays) * 24 * 3600))
        try db.execute(sql: "DELETE FROM quota_snapshots WHERE timestamp < ?", arguments: [cutoff])
    }
}
