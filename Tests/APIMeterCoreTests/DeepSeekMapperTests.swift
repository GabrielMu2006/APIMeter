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
        #expect(day22?.amount == nil)  // quantities only, never money
        #expect(day22?.verification == .official)

        let day23 = mapping.records.first { $0.day == LocalDay("2026-07-23")! }
        #expect(day23?.cacheHitTokens == nil)  // absent type stays nil
        #expect(day23?.inputTokens == 4000)
        #expect(day23?.totalTokens == 9000)
        #expect(day23?.requestCount == 3)
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
