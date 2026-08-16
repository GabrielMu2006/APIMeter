import Foundation

public enum CSVParseError: Error, LocalizedError, Equatable {
    case invalidEncoding
    case invalidQuoting

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "The CSV file is not valid UTF-8 (with or without BOM)."
        case .invalidQuoting: return "The CSV file contains invalid quoting."
        }
    }
}

/// RFC 4180-style CSV tokenizer. Schema-agnostic: it knows nothing about
/// DeepSeek fields - it only turns bytes into rows of strings.
public enum CSVParser {

    /// Parses UTF-8 data (BOM tolerated). Throws .invalidEncoding for other encodings
    /// instead of guessing (GBK files must be converted by the user first).
    public static func parse(data: Data) throws -> [[String]] {
        var text: String?
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            text = String(data: data.dropFirst(3), encoding: .utf8)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard let text else { throw CSVParseError.invalidEncoding }
        return parse(text)
    }

    // NOTE: iterates Unicode SCALARS, not Characters. In Swift, the CRLF pair
    // forms a single grapheme cluster (one Character), which would silently
    // defeat \r / \n matching when iterating Characters.
    public static func parse(_ content: String) -> [[String]] {
        let scalars = Array(content.unicodeScalars)
        let comma = UnicodeScalar(",")
        let quote = UnicodeScalar("\"")
        let cr = UnicodeScalar("\r")
        let lf = UnicodeScalar("\n")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = 0

        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == quote {
                    if i + 1 < scalars.count, scalars[i + 1] == quote {
                        field.unicodeScalars.append(quote)
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.unicodeScalars.append(c)
                i += 1
                continue
            }
            if c == quote {
                if field.isEmpty {
                    inQuotes = true
                } else {
                    // Tolerate quotes appearing mid-field (common in real-world exports).
                    field.unicodeScalars.append(quote)
                }
                i += 1
            } else if c == comma {
                row.append(field)
                field = ""
                i += 1
            } else if c == cr {
                if i + 1 < scalars.count, scalars[i + 1] == lf { i += 1 }
                row.append(field)
                field = ""
                rows.append(row)
                row = []
                i += 1
            } else if c == lf {
                row.append(field)
                field = ""
                rows.append(row)
                row = []
                i += 1
            } else {
                field.unicodeScalars.append(c)
                i += 1
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        // Drop completely empty lines (a trailing newline produces one).
        return rows.filter { row in !(row.count == 1 && row[0].isEmpty) }
    }
}
