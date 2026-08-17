import Foundation
import Testing
import Foundation
import APIMeterCore

struct AggregationTests {

    @Test func officialCSVOverridesGatewayForSameDay() {
        let day = LocalDay("2026-08-16")!
        let fp = "FP1"
        let records = [
            UsageRecord(day: day, apiKeyFingerprint: fp, requestCount: 2, totalTokens: 200, amount: Decimal(string: "0.10"), currency: "CNY", source: .officialCSV, verification: .official),
            UsageRecord(day: day, apiKeyFingerprint: fp, requestCount: 3, totalTokens: 300, amount: Decimal(string: "0.20"), currency: "CNY", source: .officialCSV, verification: .official),
            UsageRecord(day: day, apiKeyFingerprint: fp, requestCount: 99, totalTokens: 999, amount: Decimal(string: "9.99"), currency: "CNY", source: .localGateway, verification: .estimated),
        ]
        let daily = UsageAggregator.daily(from: records)
        #expect(daily.count == 1)
        #expect(daily[0].cost == Decimal(string: "0.30"))
        #expect(daily[0].requests == 5)
        #expect(daily[0].verification == .official)
    }

    @Test func estimatedWhenOnlyGatewayData() {
        let day = LocalDay("2026-08-16")!
        let records = [
            UsageRecord(day: day, requestCount: 1, totalTokens: 10, amount: Decimal(string: "0.01"), currency: "CNY", source: .localGateway, verification: .estimated),
        ]
        let daily = UsageAggregator.daily(from: records)
        #expect(daily[0].verification == .estimated)
    }

    @Test func decimalExactnessAcrossManySmallRows() {
        // 0.10 * 1000 rows must equal exactly 100, not 99.999999... (Double would drift)
        let day = LocalDay("2026-08-16")!
        var records: [UsageRecord] = []
        for _ in 0..<1000 {
            records.append(UsageRecord(day: day, requestCount: 1, amount: Decimal(string: "0.10"), currency: "CNY", source: .officialCSV, verification: .official))
        }
        let summary = UsageAggregator.summarize(records)
        #expect(summary.cost == Decimal(string: "100.00") || summary.cost == Decimal(100))
    }

    @Test func missingMetricBecomesNilNotZero() {
        let day = LocalDay("2026-08-16")!
        let records = [
            UsageRecord(day: day, requestCount: 5, source: .officialCSV, verification: .official),  // no tokens, no amount
        ]
        let daily = UsageAggregator.daily(from: records)
        #expect(daily[0].cost == nil)
        #expect(daily[0].tokens == nil)
        #expect(daily[0].requests == 5)
    }

    @Test func perKeyDailyCostsGroupsAndSorts() {
        let d1 = LocalDay("2026-08-16")!
        let d2 = LocalDay("2026-08-17")!
        let records = [
            UsageRecord(day: d1, apiKeyFingerprint: "FP-A", amount: Decimal(string: "1.00"), source: .officialCSV, verification: .official),
            UsageRecord(day: d1, apiKeyFingerprint: "FP-B", amount: Decimal(string: "2.50"), source: .officialCSV, verification: .official),
            UsageRecord(day: d1, apiKeyFingerprint: "FP-B", amount: Decimal(string: "0.50"), source: .officialCSV, verification: .official),
            UsageRecord(day: d2, apiKeyFingerprint: "FP-A", amount: Decimal(string: "4.00"), source: .officialCSV, verification: .official),
            // billing row must be excluded
            UsageRecord(day: d2, amount: Decimal(string: "99.00"), currency: "CNY", source: .officialCSV, verification: .official),
            // rows without amount are skipped
            UsageRecord(day: d2, apiKeyFingerprint: "FP-C", requestCount: 5, source: .officialCSV, verification: .official),
        ]
        let grouped = UsageAggregator.perKeyDailyCosts(records)
        #expect(grouped[d1]?.count == 2)
        #expect(grouped[d1]?.first?.fingerprint == "FP-B")
        #expect(grouped[d1]?.first?.cost == Decimal(string: "3.00"))
        #expect(grouped[d1]?.last?.fingerprint == "FP-A")
        #expect(grouped[d2]?.count == 1)
        #expect(grouped[d2]?.first?.cost == Decimal(string: "4.00"))
    }

    @Test func daysSortChronologically() {
        let d1 = LocalDay("2026-08-16")!
        let d2 = LocalDay("2026-08-17")!
        let d3 = LocalDay("2026-07-01")!
        let records = [
            UsageRecord(day: d1, requestCount: 1, source: .officialCSV, verification: .official),
            UsageRecord(day: d2, requestCount: 1, source: .officialCSV, verification: .official),
            UsageRecord(day: d3, requestCount: 1, source: .officialCSV, verification: .official),
        ]
        let daily = UsageAggregator.daily(from: records)
        #expect(daily.map(\.day.value) == ["2026-07-01", "2026-08-16", "2026-08-17"])
    }
}
