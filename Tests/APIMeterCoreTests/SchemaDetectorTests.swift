import Foundation
import Testing
import Foundation
import APIMeterCore

struct SchemaDetectorTests {

    // SYNTHETIC fixture - clearly labeled, never treated as real data.
    @Test func detectsDailyGranularityAndRoles() {
        // Two keys per day across three days = realistic daily export shape.
        let rows: [[String]] = [
            ["date", "api_key_name", "model", "request_count", "total_tokens", "amount", "currency"],
            ["2026-07-01", "Coding", "deepseek-chat", "10", "1000", "0.50", "CNY"],
            ["2026-07-01", "Research", "deepseek-reasoner", "5", "500", "0.25", "CNY"],
            ["2026-07-02", "Coding", "deepseek-chat", "20", "2000", "1.00", "CNY"],
            ["2026-07-02", "Research", "deepseek-reasoner", "8", "800", "0.40", "CNY"],
            ["2026-07-03", "Coding", "deepseek-chat", "30", "3000", "1.50", "CNY"],
            ["2026-07-03", "Research", "deepseek-reasoner", "9", "900", "0.45", "CNY"],
        ]
        let analysis = CSVSchemaDetector.analyze(rows: rows, sourceName: "synthetic.csv")
        #expect(analysis.granularity == .daily)
        #expect(analysis.dateColumnCandidates.contains("date"))
        #expect(analysis.apiKeyCandidates.contains("api_key_name"))
        #expect(analysis.tokenCandidates.contains("total_tokens"))
        #expect(analysis.amountCandidates.contains("amount"))
        #expect(analysis.modelCandidates.contains("model"))
        #expect(analysis.requestCountCandidates.contains("request_count"))
        #expect(analysis.currencyCandidates.contains("currency"))
    }

    @Test func detectsPerRowGranularity() {
        // 50 rows on 50 distinct dates (one request per row) => perRow.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        var rows: [[String]] = [["timestamp", "tokens"]]
        for i in 0..<50 {
            let date = calendar.date(byAdding: .day, value: i, to: base)!
            let stamp = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: false))
            rows.append([stamp, String(i)])
        }
        let analysis = CSVSchemaDetector.analyze(rows: rows, sourceName: "synthetic-perrow.csv")
        #expect(analysis.granularity == .perRow)
    }

    @Test func reportsMissingColumnsHonestly() {
        let rows: [[String]] = [["foo", "bar"], ["1", "2"]]
        let analysis = CSVSchemaDetector.analyze(rows: rows, sourceName: "unknown.csv")
        #expect(analysis.apiKeyCandidates.isEmpty)
        #expect(analysis.notes.contains { $0.contains("No date/timestamp-like column") })
    }
}
