import GRDB

/// Migration v1 — the first schema version (spec §72–76, §102).
/// Dates are UTC ISO8601 TEXT; money is exact decimal TEXT; day is the
/// user-local "yyyy-MM-dd" bucket computed at import time.
enum V1Initial {
    static func createTables(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS balance_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                is_available INTEGER NOT NULL DEFAULT 1,
                total TEXT NOT NULL,
                granted TEXT,
                topped_up TEXT,
                currency TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS api_keys (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fingerprint TEXT NOT NULL UNIQUE,
                display_name TEXT,
                official_name TEXT,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS usage_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT,
                day TEXT NOT NULL,
                api_key_id INTEGER REFERENCES api_keys(id),
                model TEXT,
                request_count INTEGER,
                cache_hit_tokens INTEGER,
                cache_miss_tokens INTEGER,
                input_tokens INTEGER,
                output_tokens INTEGER,
                total_tokens INTEGER,
                amount TEXT,
                currency TEXT,
                source TEXT NOT NULL,
                verification_state TEXT NOT NULL,
                source_row_hash TEXT UNIQUE,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_usage_day ON usage_records(day);
            CREATE INDEX IF NOT EXISTS idx_usage_key_day ON usage_records(api_key_id, day);

            CREATE TABLE IF NOT EXISTS import_batches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_hash TEXT NOT NULL UNIQUE,
                filename TEXT,
                month TEXT,
                imported_at TEXT NOT NULL,
                row_count INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS price_rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                provider TEXT NOT NULL DEFAULT 'deepseek',
                model TEXT NOT NULL,
                effective_from TEXT NOT NULL,
                effective_to TEXT,
                period TEXT,
                cache_hit_price TEXT,
                cache_miss_price TEXT,
                output_price TEXT,
                currency TEXT NOT NULL
            );
            """)
    }
}
