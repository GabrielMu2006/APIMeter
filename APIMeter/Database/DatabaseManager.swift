import Foundation
import GRDB

/// Owns the SQLite database and the migration pipeline (spec §102).
/// Every schema change from v1 on MUST go through the GRDB migrator.
public final class DatabaseManager: Sendable {
    public let dbQueue: DatabaseQueue
    public let path: String

    /// Current schema version, mirrored into PRAGMA user_version (spec 102).
    public static let currentSchemaVersion = 1

    public init(path: String) throws {
        self.path = path
        self.dbQueue = try DatabaseQueue(path: path)
        try migrateIfNeeded()
    }

    /// In-memory database (tests / dry runs only).
    public static func ephemeral() throws -> DatabaseManager {
        let queue = try DatabaseQueue()
        let manager = DatabaseManager(unsafeQueue: queue, path: ":memory:")
        try manager.migrateIfNeeded()
        return manager
    }

    public func migrateIfNeeded() throws {
        try Self.migrator.migrate(dbQueue)
        // GRDB tracks applied migrations in grdb_migrations; mirror the
        // version into PRAGMA user_version for external tooling (spec 102).
        try dbQueue.write { db in
            try db.execute(sql: "PRAGMA user_version = \(Self.currentSchemaVersion)")
        }
    }

    private init(unsafeQueue: DatabaseQueue, path: String) {
        self.dbQueue = unsafeQueue
        self.path = path
    }

    /// ~/Library/Application Support/APIMeter/apimeter.sqlite
    public static func defaultLocation() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("APIMeter", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("apimeter.sqlite")
    }

    /// Current schema version (PRAGMA user_version, maintained by GRDB's migrator).
    public var schemaVersion: Int {
        get throws { try dbQueue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") ?? 0 } }
    }

    public static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try V1Initial.createTables(in: db)
        }
        return migrator
    }()
}
