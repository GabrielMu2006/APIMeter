import Foundation
import GRDB
import Testing
@testable import APIMeterCore

/// Migration v2 + quota snapshot storage roundtrip + retention pruning.
struct QuotaSnapshotStoreTests {

    private func sampleQuota(fetchedAt: Date = Date()) -> CodingPlanQuota {
        CodingPlanQuota(
            planLevel: "pro",
            windows: [
                QuotaWindow(
                    kind: .fiveHour,
                    usedPercent: 37,
                    usedValue: 3700,
                    totalValue: 10000,
                    remaining: 6300,
                    resetsAt: Date(timeIntervalSince1970: 1789752000),
                    modelDetails: [QuotaModelDetail(modelCode: "GLM-5.3", usage: 3000)]
                ),
                QuotaWindow(
                    kind: .weekly,
                    usedPercent: 61,
                    usedValue: 61000,
                    totalValue: 100000,
                    remaining: 39000,
                    resetsAt: Date(timeIntervalSince1970: 1789948800),
                    modelDetails: []
                ),
            ],
            fetchedAt: fetchedAt
        )
    }

    @Test func migrationReachesVersion2() throws {
        let database = try DatabaseManager.ephemeral()
        #expect(try database.schemaVersion == 2)
    }

    @Test func saveAndLatestRoundtrip() throws {
        let database = try DatabaseManager.ephemeral()
        let repository = UsageRepository(database: database)
        try repository.saveQuotaSnapshot(sampleQuota(), provider: ZCodeRegion.bigmodelCN.rawValue)

        let latest = try repository.latestQuotaSnapshot(provider: ZCodeRegion.bigmodelCN.rawValue)
        #expect(latest?.planLevel == "pro")
        #expect(latest?.fiveHour?.usedPercent == 37)
        #expect(latest?.fiveHour?.usedValue == 3700)
        #expect(latest?.fiveHour?.totalValue == 10000)
        #expect(latest?.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1789752000))
        #expect(latest?.fiveHour?.modelDetails == [QuotaModelDetail(modelCode: "GLM-5.3", usage: 3000)])
        #expect(latest?.weekly?.usedPercent == 61)
        // Regions do not mix.
        #expect(try repository.latestQuotaSnapshot(provider: ZCodeRegion.zaiGlobal.rawValue) == nil)
    }

    @Test func latestPrefersNewestTimestamp() throws {
        let database = try DatabaseManager.ephemeral()
        let repository = UsageRepository(database: database)
        // Both timestamps must stay inside the 30-day retention window, at
        // whole seconds (storage truncates to seconds).
        let base = Date(timeIntervalSince1970: Double(Int(Date().timeIntervalSince1970)))
        let old = sampleQuota(fetchedAt: base.addingTimeInterval(-60))
        let newer = sampleQuota(fetchedAt: base)
        try repository.saveQuotaSnapshot(old, provider: ZCodeRegion.bigmodelCN.rawValue)
        try repository.saveQuotaSnapshot(newer, provider: ZCodeRegion.bigmodelCN.rawValue)
        let latest = try repository.latestQuotaSnapshot(provider: ZCodeRegion.bigmodelCN.rawValue)
        #expect(latest?.fetchedAt == newer.fetchedAt)
    }

    @Test func retentionPrunesOldSnapshots() throws {
        let database = try DatabaseManager.ephemeral()
        let repository = UsageRepository(database: database)
        // A fresh save inserts current rows.
        try repository.saveQuotaSnapshot(sampleQuota(), provider: ZCodeRegion.bigmodelCN.rawValue)
        #expect(try repository.latestQuotaSnapshot(provider: ZCodeRegion.bigmodelCN.rawValue) != nil)

        // Rows older than the retention window vanish on the next write.
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE quota_snapshots SET timestamp = ?",
                arguments: [ISO8601.string(Date().addingTimeInterval(-Double(V2QuotaSnapshots.retentionDays + 1) * 24 * 3600))]
            )
        }
        try repository.saveQuotaSnapshot(sampleQuota(), provider: ZCodeRegion.bigmodelCN.rawValue)
        let oldRows = try database.dbQueue.read { db in
            try QuotaSnapshotRow.filter(Column("used_percent") != nil).fetchCount(db)
        }
        // Only the rows from the two "now" saves remain; the aged rows were pruned.
        #expect(oldRows > 0)
        let staleCount = try database.dbQueue.read { db in
            try QuotaSnapshotRow
                .filter(Column("timestamp") < ISO8601.string(Date().addingTimeInterval(-Double(V2QuotaSnapshots.retentionDays) * 24 * 3600)))
                .fetchCount(db)
        }
        #expect(staleCount == 0)
    }
}
