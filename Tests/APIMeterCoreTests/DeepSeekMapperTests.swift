import Foundation
import Testing
import APIMeterCore

/// Mapper tests. Fixtures mirror the REAL DeepSeek export structure
/// (docs/deepseek-csv-schema.md) but contain SYNTHETIC values only.
struct DeepSeekMapperTests {

    // Synthetic rows in the exact real shape of the amount file.
    private let amountRows: [[String]] = [
        ["user_id", "start_time_iso", "end_time_iso", "model", "api_key_name", "api_key", "type", "price", "amount"],
        ["acct-1", "2026-07-22T00:00:00+08:00", "2026-07-23T00:00:00+08:00", "deepseek-v4-pro", "Coding", "sk-92063***********************e267", "input_cache_hit_tokens", "0.000000025", "1000"],
        ["acct-1", "2026-07-22T00:00:00+08:00", "2026-07-23T00:00:00+08:00", "deepseek-v4-pro", "Coding", "sk-92063***********************e267", "input_cache_miss_tokens", "0.000003", "2000"],
        ["acct-1", "2026-07-22T00:00:00+08:00", "2026-07-23T00:00:00+08:00", "deepseek-v4-pro", "Coding", "sk-92063***********************e267", "output_tokens", "0.000006", "3000"],
        ["acct-1", "2026-07-22T00:00:00+08:00", "2026-07-23T00:00:00+08:00", "deepseek-v4-pro", "Coding", "sk-92063***********************e267", "request_count", "", "7"],
        ["acct-1", "2026-07-23T00:00:00+08:00", "2026-07-24T00:00:00+08:00", "deepseek-v4-pro", "Research", "sk-3dcd2***********************2b7f", "input_cache_miss_tokens", "0.000003", "4000"],
        ["acct-1", "2026-07-23T00:00:00+08:00", "2026-07-24T00:00:00+08:00", "deepseek-v4-pro", "Research", "sk-3dcd2***********************2b7f", "output_tokens", "0.000006", "5000"],
        ["acct-1", "2026-07-23T00:00:00+08:00", "2026-07-24T00:00:00+08:00", "deepseek-v4-pro", "Research", "sk-3dcd2***********************2b7f", "request_count", "", "3"],
    ];

    private let costRows: [[String]] = [
        ["user_id", "start_time_iso", "end_time_iso", "model", "wallet_type", "cost", "currency"],
        ["acct-1", "2026-07-22T00:00:00+08:00", "2026-07-23T00:00:00+08:00", "deepseek-v4-pro", "Paid", "1.2345000000000000", "CNY"],
        ["acct-1", "2026-07-23T00:00:00+08:00", "2026-07-24T00:00:00+08:00", "deepseek-v4-pro", "Paid", "0.9876000000000000", "CNY"],
    ];

    @Test func detectsFileKinds() throws {
        #expect(try DeepSeekOfficialCSVMapper.detectKind(rows: amountRows) == .amount)
        #expect(try DeepSeekOfficialCSVMapper.detectKind(rows: costRows) == .cost)
    }

    @Test func mapsAmountRowsIntoGroupedRecords() throws {
        let mapper = DeepSeekOfficialCSVMapper()
        let mapping = try mapper.map(rows: amountRows)
        // 4 rows day 22 (one key) + 3 rows day 23 (one key) = 2 records
        #expect(mapping.records.count == 2)

        let day22 = mapping.records.first { $0.day == LocalDay("2026-07-22")! }
        #expect(day22?.requestCount == 7)
        #expect(day22?.cacheHitTokens == 1000)
        #expect(day22?.cacheMissTokens == 2000)
        #expect(day22?.outputTokens == 3000)
        #expect(day22?.inputTokens == 3000)
        #expect(day22?.totalTokens == 6000)
        // Derived per-key cost = price * amount per row (official arithmetic):
        // 1000*0.000000025 + 2000*0.000003 + 3000*0.000006 = 0.024025
        #expect(day22?.amount == Decimal(string: "0.024025"))
        #expect(day22?.currency == nil)  // filled by reconciliation against the cost file
        #expect(day22?.verification == .official)

        let day23 = mapping.records.first { $0.day == LocalDay("2026-07-23")! }
        #expect(day23?.cacheHitTokens == nil)  // absent type stays nil
        #expect(day23?.inputTokens == 4000)
        #expect(day23?.totalTokens == 9000)
        #expect(day23?.requestCount == 3)
        // 4000*0.000003 + 5000*0.000006 = 0.042
        #expect(day23?.amount == Decimal(string: "0.042"))
    }

    @Test func extractsKeyNamesAndPriceRules() throws {
        let mapper = DeepSeekOfficialCSVMapper()
        let mapping = try mapper.map(rows: amountRows)
        let names = Dictionary(uniqueKeysWithValues: mapping.keyNames.map { ($0.fingerprint, $0.officialName) })
        #expect(names.values.sorted() == ["Coding", "Research"])
        #expect(mapping.priceRules.count == 5)  // 5 rows with prices
        let hitRule = mapping.priceRules.first { $0.cacheHitPrice != nil }
        #expect(hitRule?.cacheHitPrice == Decimal(string: "0.025"))  // 0.000000025 per token * 1M
    }

    @Test func mapsCostRowsWithoutKey() throws {
        let mapper = DeepSeekOfficialCSVMapper()
        let mapping = try mapper.map(rows: costRows)
        #expect(mapping.records.count == 2)
        let first = mapping.records[0]
        #expect(first.amount == Decimal(string: "1.2345"))
        #expect(first.currency == "CNY")
        #expect(first.apiKeyFingerprint == nil)  // cost is not key-attributed
        #expect(first.requestCount == nil)
        #expect(first.totalTokens == nil)
        #expect(first.day == LocalDay("2026-07-22")!)
    }

    @Test func unknownTypeThrows() throws {
        var rows = amountRows
        rows[1][6] = "some_future_type"
        let mapper = DeepSeekOfficialCSVMapper()
        #expect(throws: ImportError.self) {
            _ = try mapper.map(rows: rows)
        }
    }

    @Test func billingRowsAreAuthoritativeForDayTotal() {
        let day = LocalDay("2026-07-22")!
        let records = [
            // Billing row: cost file, no key (2.949298 for the day+model).
            UsageRecord(day: day, model: "m", amount: Decimal(string: "2.949298"), currency: "CNY", source: .officialCSV, verification: .official),
            // Keyed rows: derived per-key cost from the amount file.
            UsageRecord(day: day, apiKeyFingerprint: "FP1", model: "m", requestCount: 100, totalTokens: 1000, amount: Decimal(string: "1.50"), currency: nil, source: .officialCSV, verification: .official),
            UsageRecord(day: day, apiKeyFingerprint: "FP2", model: "m", requestCount: 45, totalTokens: 500, amount: Decimal(string: "1.449298"), currency: nil, source: .officialCSV, verification: .official),
        ]
        let daily = UsageAggregator.daily(from: records)
        // Day total = billing, NOT billing + derived (no double counting).
        #expect(daily[0].cost == Decimal(string: "2.949298"))
        #expect(daily[0].requests == 145)
        #expect(daily[0].tokens == 1500)
        #expect(daily[0].verification == .official)
        // Per-key breakdown carries the derived amounts.
        let summary = UsageAggregator.summarize(records)
        let fp1 = summary.byAPIKey.first { $0.fingerprint == "FP1" }
        #expect(fp1?.cost == Decimal(string: "1.50"))
        let fp2 = summary.byAPIKey.first { $0.fingerprint == "FP2" }
        #expect(fp2?.cost == Decimal(string: "1.449298"))
        // Billing rows must not appear as an "(unknown)" key.
        #expect(summary.byAPIKey.contains { $0.fingerprint == "(unknown)" } == false)
    }

    @Test func derivedCostSumsToDayWhenNoBillingRows() {
        let day = LocalDay("2026-07-22")!
        let records = [
            UsageRecord(day: day, apiKeyFingerprint: "FP1", model: "m", amount: Decimal(string: "1.20"), source: .officialCSV, verification: .official),
            UsageRecord(day: day, apiKeyFingerprint: "FP2", model: "m", amount: Decimal(string: "0.80"), source: .officialCSV, verification: .official),
        ]
        let daily = UsageAggregator.daily(from: records)
        #expect(daily[0].cost == Decimal(string: "2.00"))
        #expect(daily[0].verification == .official)
    }

    @Test func mixedCostAndQuantityAggregateToOneDay() {
        // Real data shape: cost records carry money, quantity records carry
        // tokens/requests; one day gets both kinds of official rows.
        let day = LocalDay("2026-07-22")!
        let records = [
            UsageRecord(day: day, model: "m", amount: Decimal(string: "1.23"), currency: "CNY", source: .officialCSV, verification: .official),
            UsageRecord(day: day, apiKeyFingerprint: "FP", model: "m", requestCount: 5, totalTokens: 100, source: .officialCSV, verification: .official),
        ]
        let daily = UsageAggregator.daily(from: records)
        #expect(daily.count == 1)
        #expect(daily[0].cost == Decimal(string: "1.23"))
        #expect(daily[0].requests == 5)
        #expect(daily[0].tokens == 100)
        #expect(daily[0].verification == .official)
    }
}
