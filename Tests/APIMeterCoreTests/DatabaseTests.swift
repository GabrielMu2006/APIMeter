import Foundation
import Testing
import Foundation
import APIMeterCore

struct DatabaseTests {

    @Test func migrationV1CreatesSchema() throws {
        let db = try DatabaseManager.ephemeral()
        #expect(try db.schemaVersion == 1)
    }

    @Test func upsertAndRowDedup() throws {
        let db = try DatabaseManager.ephemeral()
        let repo = UsageRepository(database: db)
        let day = LocalDay("2026-08-16")!
        var record = UsageRecord(day: day, apiKeyFingerprint: "FP1", model: "deepseek-chat", requestCount: 1, totalTokens: 10, amount: Decimal(string: "0.05"), currency: "CNY", source: .officialCSV, verification: .official)
        var stats = try repo.upsert([record])
        #expect(stats.inserted == 1)
        stats = try repo.upsert([record])
        #expect(stats.inserted == 0)
        #expect(stats.ignoredDuplicates == 1)
        #expect(try repo.recordCount() == 1)
    }

    @Test func apiKeyRowCreatedLazilyAndRenameable() throws {
        let db = try DatabaseManager.ephemeral()
        let repo = UsageRepository(database: db)
        let day = LocalDay("2026-08-16")!
        let record = UsageRecord(day: day, apiKeyFingerprint: "FPX", requestCount: 1, source: .officialCSV, verification: .official)
        _ = try repo.upsert([record])
        var keys = try repo.fetchAPIKeys()
        #expect(keys.count == 1)
        #expect(keys[0].fingerprint == "FPX")
        try repo.setDisplayName("Coding", fingerprint: "FPX")
        keys = try repo.fetchAPIKeys()
        #expect(keys[0].displayName == "Coding")
    }

    @Test func balanceSnapshotRoundtrip() throws {
        let db = try DatabaseManager.ephemeral()
        let repo = UsageRepository(database: db)
        let balance = Balance(
            isAvailable: true,
            balanceInfos: [BalanceInfo(currency: "CNY", totalBalance: Decimal(string: "32.34")!, grantedBalance: Decimal(string: "10.00")!, toppedUpBalance: Decimal(string: "22.34")!)],
            fetchedAt: Date()
        )
        try repo.saveBalanceSnapshot(balance)
        let latest = try repo.latestBalanceSnapshot()
        #expect(latest?.balanceInfos.first?.totalBalance == Decimal(string: "32.34"))
    }

    @Test func retentionDeletesOldButKeepsImportBatches() throws {
        let db = try DatabaseManager.ephemeral()
        let repo = UsageRepository(database: db)
        let oldDay = LocalDay("2026-01-01")!
        let recentDay = LocalDay("2026-08-16")!
        _ = try repo.upsert([UsageRecord(day: oldDay, requestCount: 1, source: .officialCSV, verification: .official)])
        _ = try repo.upsert([UsageRecord(day: recentDay, requestCount: 1, source: .officialCSV, verification: .official)])
        try repo.recordImportBatch(ImportBatch(fileHash: "H1", filename: "jan.zip", month: "2026-01", importedAt: Date(), rowCount: 1))
        let now = LocalDay("2026-08-16")!
        let deleted = try repo.applyRetention(.days30, now: now)
        #expect(deleted == 1)
        #expect(try repo.recordCount() == 1)
        // import batch metadata survives retention
        #expect(try repo.fetchImportBatches().count == 1)
    }

    @Test func apiKeyFilterInDailyQuery() throws {
        let db = try DatabaseManager.ephemeral()
        let repo = UsageRepository(database: db)
        let day = LocalDay("2026-08-16")!
        _ = try repo.upsert([UsageRecord(day: day, apiKeyFingerprint: "FP-A", requestCount: 1, amount: Decimal(string: "1.00"), currency: "CNY", source: .officialCSV, verification: .official)])
        _ = try repo.upsert([UsageRecord(day: day, apiKeyFingerprint: "FP-B", requestCount: 1, amount: Decimal(string: "2.00"), currency: "CNY", source: .officialCSV, verification: .official)])
        let all = try repo.dailyUsage(from: day, to: day)
        #expect(all.first?.cost == Decimal(string: "3.00"))
        let filtered = try repo.dailyUsage(from: day, to: day, fingerprints: ["FP-A"])
        #expect(filtered.first?.cost == Decimal(string: "1.00"))
    }
}
