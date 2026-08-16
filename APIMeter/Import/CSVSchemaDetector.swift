import Foundation

/// Result of analyzing a real usage export file.
/// This is ANALYSIS ONLY - the detector reports what it sees and never
/// invents or interprets beyond the facts (spec 14/117).
public struct CSVAnalysis: Equatable, Sendable {

    public struct ColumnProfile: Equatable, Sendable {
        public let name: String
        public let index: Int
        public let nonEmptyCount: Int
        public let distinctCount: Int
        public let numericRatio: Double
        public let dateLikeRatio: Double
        public let samples: [String]
    }

    public enum Granularity: String, Equatable, Sendable {
        case empty
        case singleRow
        case perRow
        case daily
        case singleDate
        case unknown
    }

    public let sourceName: String
    public let rowCount: Int
    public let header: [String]
    public let columns: [ColumnProfile]
    public let granularity: Granularity
    public let dateColumnCandidates: [String]
    public let timestampColumnCandidates: [String]
    public let apiKeyCandidates: [String]
    public let tokenCandidates: [String]
    public let amountCandidates: [String]
    public let modelCandidates: [String]
    public let requestCountCandidates: [String]
    public let currencyCandidates: [String]
    public let notes: [String]

    /// Markdown report ready to paste into docs/deepseek-csv-schema.md.
    public func markdownReport() -> String {
        let fence = String(repeating: Character(UnicodeScalar(96)), count: 3)
        var out: [String] = []
        out.append("# DeepSeek Usage Export - Schema Analysis")
        out.append("")
        out.append("- Source file: " + sourceName)
        out.append("- Data rows: " + String(rowCount))
        out.append("- Detected granularity: **" + granularity.rawValue + "**")
        out.append("")
        out.append("## Header")
        out.append("")
        out.append(fence + "text")
        out.append(header.enumerated().map { String($0.offset) + ": " + $0.element }.joined(separator: "\n"))
        out.append(fence)
        out.append("")
        out.append("## Columns")
        out.append("")
        out.append("| # | Column | Non-empty | Distinct | Numeric % | Date-like % | Samples |")
        out.append("|---|--------|-----------|----------|-----------|-------------|---------|")
        for column in columns {
            let samples = column.samples.prefix(3).map { $0.replacingOccurrences(of: "|", with: "/") }.joined(separator: "; ")
            out.append("| " + String(column.index) + " | " + column.name + " | " + String(column.nonEmptyCount) + " | " + String(column.distinctCount) + " | " + String(Int(column.numericRatio * 100)) + " | " + String(Int(column.dateLikeRatio * 100)) + " | " + samples + " |")
        }
        out.append("")
        out.append("## Field roles")
        out.append("")
        func line(_ title: String, _ values: [String]) {
            out.append("- " + title + ": " + (values.isEmpty ? "(none detected)" : values.map { "'" + $0 + "'" }.joined(separator: ", ")))
        }
        line("Date", dateColumnCandidates)
        line("Timestamp", timestampColumnCandidates)
        line("API Key", apiKeyCandidates)
        line("Tokens", tokenCandidates)
        line("Amount", amountCandidates)
        line("Model", modelCandidates)
        line("Request count", requestCountCandidates)
        line("Currency", currencyCandidates)
        out.append("")
        out.append("## Notes")
        out.append("")
        if notes.isEmpty {
            out.append("(none)")
        } else {
            out.append(contentsOf: notes.map { "- " + $0 })
        }
        return out.joined(separator: "\n")
    }
}

public enum CSVSchemaDetector {

    /// Analyzes parsed rows. Expects row 0 to be the header (typical export format).
    public static func analyze(rows: [[String]], sourceName: String) -> CSVAnalysis {
        guard !rows.isEmpty else {
            return CSVAnalysis(sourceName: sourceName, rowCount: 0, header: [], columns: [],
                               granularity: .empty, dateColumnCandidates: [], timestampColumnCandidates: [],
                               apiKeyCandidates: [], tokenCandidates: [], amountCandidates: [],
                               modelCandidates: [], requestCountCandidates: [], currencyCandidates: [],
                               notes: ["File contains no rows."])
        }
        let header = rows[0]
        let dataRows = Array(rows.dropFirst())
        let rowCount = dataRows.count

        var columns: [CSVAnalysis.ColumnProfile] = []
        for (index, name) in header.enumerated() {
            let values = dataRows.map { index < $0.count ? $0[index] : "" }
            let nonEmpty = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let distinct = Set(nonEmpty.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }).count
            let numeric = nonEmpty.filter { isNumeric($0) }.count
            let dateLike = nonEmpty.filter { isDateLike($0) }.count
            columns.append(CSVAnalysis.ColumnProfile(
                name: name,
                index: index,
                nonEmptyCount: nonEmpty.count,
                distinctCount: distinct,
                numericRatio: nonEmpty.isEmpty ? 0 : Double(numeric) / Double(nonEmpty.count),
                dateLikeRatio: nonEmpty.isEmpty ? 0 : Double(dateLike) / Double(nonEmpty.count),
                samples: Array(nonEmpty.prefix(5))
            ))
        }

        func candidates(_ predicate: (String) -> Bool) -> [String] {
            header.filter { predicate(normalize($0)) }
        }

        let dateCandidates = candidates { $0.contains("date") || $0 == "day" }
        let timestampCandidates = candidates { $0.contains("time") || $0.contains("created") || $0.contains("datetime") }
        let apiKeyCandidates = candidates { $0.contains("key") || $0.contains("api") }
        let tokenCandidates = candidates { $0.contains("token") }
        let amountCandidates = candidates { name in
            ["amount", "cost", "price", "fee", "spend", "charge", "consumption"].contains { name.contains($0) }
        }
        let modelCandidates = candidates { $0.contains("model") }
        let requestCountCandidates = candidates { $0.contains("request") || $0.contains("count") }
        let currencyCandidates = candidates { $0.contains("currency") }

        var notes: [String] = []
        let granularity = detectGranularity(header: header, dataRows: dataRows, dateNames: dateCandidates, timestampNames: timestampCandidates, rowCount: rowCount, notes: &notes)
        if dateCandidates.isEmpty && timestampCandidates.isEmpty {
            notes.append("No date/timestamp-like column detected - daily aggregation may be impossible.")
        }
        if apiKeyCandidates.isEmpty {
            notes.append("No API key column detected - per-key breakdown may be impossible.")
        }

        return CSVAnalysis(
            sourceName: sourceName,
            rowCount: rowCount,
            header: header,
            columns: columns,
            granularity: granularity,
            dateColumnCandidates: dateCandidates,
            timestampColumnCandidates: timestampCandidates,
            apiKeyCandidates: apiKeyCandidates,
            tokenCandidates: tokenCandidates,
            amountCandidates: amountCandidates,
            modelCandidates: modelCandidates,
            requestCountCandidates: requestCountCandidates,
            currencyCandidates: currencyCandidates,
            notes: notes
        )
    }

    // MARK: - Internals

    private static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func isNumeric(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Double(trimmed) != nil
    }

    private static func isDateLike(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if ISO8601.date(trimmed) != nil { return true }
        let patterns = [
            #"^\d{4}-\d{2}-\d{2}$"#,
            #"^\d{4}/\d{2}/\d{2}$"#,
            #"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$"#,
            #"^\d{4}/\d{2}/\d{2}[ T]\d{2}:\d{2}(:\d{2})?$"#,
            #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#,
            #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$"#,
        ]
        for pattern in patterns {
            if trimmed.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        return false
    }

    private static func datePrefix(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }
        let first10 = String(trimmed.prefix(10))
        if let day = LocalDay(first10) { return day.value }
        let replaced = first10.replacingOccurrences(of: "/", with: "-")
        if let day = LocalDay(replaced) { return day.value }
        return nil
    }

    private static func detectGranularity(
        header: [String],
        dataRows: [[String]],
        dateNames: [String],
        timestampNames: [String],
        rowCount: Int,
        notes: inout [String]
    ) -> CSVAnalysis.Granularity {
        guard rowCount > 0 else { return .empty }
        if rowCount == 1 { return .singleRow }

        guard let name = (dateNames + timestampNames).first,
              let index = header.firstIndex(of: name) else {
            return .unknown
        }
        let values = dataRows.map { index < $0.count ? $0[index] : "" }
        let prefixes = Set(values.compactMap(datePrefix))
        let distinct = prefixes.count

        if distinct == 1 {
            return .singleDate
        }
        let ratio = Double(distinct) / Double(rowCount)
        if ratio >= 0.9 {
            return .perRow
        }
        if distinct <= 31 {
            return .daily
        }
        notes.append("Column " + name + ": " + String(distinct) + " distinct dates across " + String(rowCount) + " rows - granularity could not be auto-classified.")
        return .unknown
    }
}
