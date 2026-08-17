import Foundation
import Testing
@testable import APIMeterCore

struct UsageExportTests {

    @Test func csvHeaderMatchesSpec() {
        let csv = UsageExportService.csvData(records: [])
        #expect(csv == "date,api_key,cost,requests,tokens,source,verification\n")
    }

    @Test func csvEscapesCommasAndQuotes() {
        #expect(UsageExportService.escape("plain") == "plain")
        #expect(UsageExportService.escape("a,b") == "\"a,b\"")
        #expect(UsageExportService.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func csvRowsCarryAllFields() {
        let day = LocalDay("2026-08-17")!
        let record = UsageRecord(
            day: day,
            apiKeyFingerprint: "FP1",
            model: "m",
            requestCount: 124,
            totalTokens: 22_877_982,
            amount: Decimal(string: "6.03"),
            currency: "CNY",
            source: .officialCSV,
            verification: .official
        )
        let csv = UsageExportService.csvData(records: [record])
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[1] == "2026-08-17,FP1,6.03,124,22877982,officialCSV,official")
    }

    @Test func missingFieldsStayEmpty() {
        let day = LocalDay("2026-08-17")!
        let record = UsageRecord(day: day, source: .localGateway, verification: .estimated)
        let csv = UsageExportService.csvData(records: [record])
        #expect(csv.contains("2026-08-17,,,,,localGateway,estimated"))
    }
}
