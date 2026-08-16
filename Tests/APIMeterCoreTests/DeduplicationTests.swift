import Foundation
import Testing
import Foundation
import APIMeterCore

struct DeduplicationTests {

    @Test func fileHashIsStable() {
        let a = ImportDeduplicator.fileHash(Data("hello".utf8))
        let b = ImportDeduplicator.fileHash(Data("hello".utf8))
        let c = ImportDeduplicator.fileHash(Data("world".utf8))
        #expect(a == b)
        #expect(a != c)
    }

    @Test func rowHashIgnoresVerificationState() {
        let day = LocalDay("2026-08-16")!
        var official = UsageRecord(day: day, amount: Decimal(string: "1.5"), currency: "CNY", source: .officialCSV, verification: .official)
        var estimated = UsageRecord(day: day, amount: Decimal(string: "1.5"), currency: "CNY", source: .localGateway, verification: .estimated)
        official.source = .officialCSV
        estimated.source = .officialCSV
        let h1 = ImportDeduplicator.rowHash(official)
        let h2 = ImportDeduplicator.rowHash(estimated)
        // Same canonical content (source normalized) collapses across overlapping exports.
        #expect(h1 == h2)
    }

    @Test func rowHashDistinguishesTimestamps() {
        let day = LocalDay("2026-08-16")!
        let t1 = Date(timeIntervalSince1970: 1_700_000_000.1)
        let t2 = Date(timeIntervalSince1970: 1_700_000_000.2)
        let r1 = UsageRecord(timestamp: t1, day: day, source: .localGateway, verification: .estimated)
        let r2 = UsageRecord(timestamp: t2, day: day, source: .localGateway, verification: .estimated)
        #expect(ImportDeduplicator.rowHash(r1) != ImportDeduplicator.rowHash(r2))
    }
}
