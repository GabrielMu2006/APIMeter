import Foundation

/// Local CSV export (spec 61):
/// date, api_key, cost, requests, tokens, source, verification
public enum UsageExportService {

    public static func csvData(records: [UsageRecord]) -> String {
        var lines = ["date,api_key,cost,requests,tokens,source,verification"]
        for record in records {
            let fields = [
                record.day.value,
                record.apiKeyFingerprint ?? "",
                record.amount.map(DecimalStorage.string) ?? "",
                record.requestCount.map(String.init) ?? "",
                record.totalTokens.map(String.init) ?? "",
                record.source.rawValue,
                record.verification.rawValue,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    public static func exportFileURL(records: [UsageRecord], to directory: URL, filename: String = "apimeter-export.csv") throws -> URL {
        let url = directory.appendingPathComponent(filename)
        try csvData(records: records).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
