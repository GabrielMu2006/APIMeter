import Foundation

/// Result of mapping one CSV file into internal models.
public struct CSVMapping: Sendable {
    public let records: [UsageRecord]
    /// (fingerprint, official api key name) pairs discovered in the file.
    public let keyNames: [(fingerprint: String, officialName: String)]
    /// Price rules derived from the export's own price column (official data).
    public let priceRules: [PriceRule]

    public init(records: [UsageRecord], keyNames: [(fingerprint: String, officialName: String)], priceRules: [PriceRule]) {
        self.records = records
        self.keyNames = keyNames
        self.priceRules = priceRules
    }
}

/// Mapper for the REAL DeepSeek official usage export format.
///
/// Schema confirmed from actual exports (2026-07/08, exported from
/// platform.deepseek.com) and documented in docs/deepseek-csv-schema.md.
/// Two file kinds exist:
///
/// 1. amount file - long format:
///    user_id,start_time_iso,end_time_iso,model,api_key_name,api_key,type,price,amount
///    type in: input_cache_hit_tokens | input_cache_miss_tokens | output_tokens | request_count
///    (api_key is MASKED by DeepSeek, e.g. sk-92063****e267)
///
/// 2. cost file:
///    user_id,start_time_iso,end_time_iso,model,wallet_type,cost,currency
///    cost is per (day, model) - no api key dimension.
///
/// Unknown type values throw - partial silent imports are forbidden (spec 82).
public struct DeepSeekOfficialCSVMapper: CSVMapper {
    public let schemaID = "deepseek-official-v1"

    public init() {}

    public enum FileKind: String, Sendable {
        case amount
        case cost
    }

    public static func detectKind(rows: [[String]]) throws -> FileKind {
        guard let header = rows.first, !header.isEmpty else { throw ImportError.emptyFile }
        let set = Set(header)
        if set.contains("type") && set.contains("amount") && set.contains("api_key") && set.contains("api_key_name") {
            return .amount
        }
        if set.contains("cost") && set.contains("currency") && set.contains("wallet_type") {
            return .cost
        }
        throw ImportError.unsupportedSchema(details: "Unknown DeepSeek export header: " + header.joined(separator: ","))
    }

    public func map(rows: [[String]]) throws -> CSVMapping {
        let kind = try Self.detectKind(rows: rows)
        switch kind {
        case .amount: return try Self.mapAmountFile(rows: rows)
        case .cost: return try Self.mapCostFile(rows: rows)
        }
    }

    // MARK: - amount file (tokens / request quantities, per key)

    private static func mapAmountFile(rows: [[String]]) throws -> CSVMapping {
        let header = rows[0]
        func column(_ name: String) -> Int {
            header.firstIndex(of: name) ?? -1
        }
        let cStart = column("start_time_iso")
        let cEnd = column("end_time_iso")
        let cModel = column("model")
        let cKeyName = column("api_key_name")
        let cKey = column("api_key")
        let cType = column("type")
        let cPrice = column("price")
        let cAmount = column("amount")
        guard cStart >= 0, cEnd >= 0, cModel >= 0, cKeyName >= 0, cKey >= 0, cType >= 0, cPrice >= 0, cAmount >= 0 else {
            throw ImportError.unsupportedSchema(details: "amount file is missing expected columns")
        }

        struct GroupKey: Hashable {
            let day: LocalDay
            let model: String
            let identity: String
        }
        struct Group {
            var model: String
            var identity: String
            var officialName: String
            var cacheHit: Int64?
            var cacheMiss: Int64?
            var output: Int64?
            var requests: Int64?
            var start: Date?
            var end: Date?
        }

        var groups: [GroupKey: Group] = [:]
        var priceRules: [PriceRule] = []
        var rulesSeen: Set<String> = []

        for row in rows.dropFirst() {
            guard row.count > max(cStart, cEnd, cModel, cKeyName, cKey, cType, cPrice, cAmount) else {
                throw ImportError.invalidDay("row with too few columns")
            }
            let startISO = row[cStart].trimmingCharacters(in: .whitespaces)
            let endISO = row[cEnd].trimmingCharacters(in: .whitespaces)
            guard let startDate = ISO8601.date(startISO) else {
                throw ImportError.invalidDay(startISO)
            }
            let endDate = ISO8601.date(endISO)
            let model = row[cModel].trimmingCharacters(in: .whitespaces)
            let keyName = row[cKeyName].trimmingCharacters(in: .whitespaces)
            let maskedKey = row[cKey].trimmingCharacters(in: .whitespaces)
            let type = row[cType].trimmingCharacters(in: .whitespaces)
            let price = row[cPrice].trimmingCharacters(in: .whitespaces)
            let amountString = row[cAmount].trimmingCharacters(in: .whitespaces)

            // The export timestamps carry their own offset (+08:00). The date
            // part in that offset IS the billing day - bucketing by the
            // timestamp's own timezone keeps history correct no matter where
            // the Mac is.
            let day = Self.day(in: startISO, fallbackDate: startDate)
            // Stable identity for the masked key (DeepSeek only exports masks).
            let identity = maskedKey.isEmpty ? ("name:" + keyName) : maskedKey

            let groupKey = GroupKey(day: day, model: model, identity: identity)
            var group = groups[groupKey] ?? Group(model: model, identity: identity, officialName: keyName)
            group.start = group.start ?? startDate
            group.end = group.end ?? endDate

            guard let amount = Int64(amountString) else {
                throw ImportError.unsupportedSchema(details: "unparseable amount value '" + amountString + "' in amount file")
            }
            switch type {
            case "input_cache_hit_tokens":
                group.cacheHit = (group.cacheHit ?? 0) + amount
            case "input_cache_miss_tokens":
                group.cacheMiss = (group.cacheMiss ?? 0) + amount
            case "output_tokens":
                group.output = (group.output ?? 0) + amount
            case "request_count":
                group.requests = (group.requests ?? 0) + amount
            default:
                throw ImportError.unsupportedSchema(details: "unknown type '" + type + "' in amount file (schema drift - refusing to guess)")
            }
            groups[groupKey] = group

            // Price rules from the export's own price column (per-token price,
            // official data). request_count rows have no price.
            if !price.isEmpty, let perToken = Decimal(string: price, locale: Locale(identifier: "en_US_POSIX")), let end = endDate {
                let perMillion = perToken * Decimal(1_000_000)
                let ruleKey = model + "|" + type + "|" + startISO + "|" + endISO
                if !rulesSeen.contains(ruleKey) {
                    rulesSeen.insert(ruleKey)
                    var rule = PriceRule(
                        provider: "deepseek",
                        model: model,
                        effectiveFrom: startDate,
                        effectiveTo: end,
                        period: .standard,
                        currency: "CNY"
                    )
                    switch type {
                    case "input_cache_hit_tokens": rule.cacheHitPrice = perMillion
                    case "input_cache_miss_tokens": rule.cacheMissPrice = perMillion
                    case "output_tokens": rule.outputPrice = perMillion
                    default: break
                    }
                    priceRules.append(rule)
                }
            }
        }

        var records: [UsageRecord] = []
        var keyNames: [(String, String)] = []
        var seenKeyNames: Set<String> = []
        for (groupKey, group) in groups {
            let hit = group.cacheHit
            let miss = group.cacheMiss
            let output = group.output
            let input: Int64?
            let total: Int64?
            if hit != nil || miss != nil {
                input = (hit ?? 0) + (miss ?? 0)
            } else {
                input = nil
            }
            if hit != nil || miss != nil || output != nil {
                total = (hit ?? 0) + (miss ?? 0) + (output ?? 0)
            } else {
                total = nil
            }
            let fingerprint = KeyFingerprint.sha256Hex(of: group.identity)
            records.append(UsageRecord(
                timestamp: group.start,
                day: groupKey.day,
                apiKeyFingerprint: fingerprint,
                model: group.model,
                requestCount: group.requests,
                cacheHitTokens: hit,
                cacheMissTokens: miss,
                inputTokens: input,
                outputTokens: output,
                totalTokens: total,
                amount: nil,
                currency: nil,
                source: .officialCSV,
                verification: .official
            ))
            if !seenKeyNames.contains(fingerprint) {
                seenKeyNames.insert(fingerprint)
                keyNames.append((fingerprint, group.officialName))
            }
        }
        records.sort { ($0.day.value, $0.model ?? "", $0.apiKeyFingerprint ?? "") < ($1.day.value, $1.model ?? "", $1.apiKeyFingerprint ?? "") }
        return CSVMapping(records: records, keyNames: keyNames, priceRules: priceRules)
    }

    // MARK: - cost file (money per day + model)

    private static func mapCostFile(rows: [[String]]) throws -> CSVMapping {
        let header = rows[0]
        func column(_ name: String) -> Int {
            header.firstIndex(of: name) ?? -1
        }
        let cStart = column("start_time_iso")
        let cModel = column("model")
        let cCost = column("cost")
        let cCurrency = column("currency")
        guard cStart >= 0, cModel >= 0, cCost >= 0, cCurrency >= 0 else {
            throw ImportError.unsupportedSchema(details: "cost file is missing expected columns")
        }
        var records: [UsageRecord] = []
        for row in rows.dropFirst() {
            guard row.count > max(cStart, cModel, cCost, cCurrency) else { continue }
            let startISO = row[cStart].trimmingCharacters(in: .whitespaces)
            guard let startDate = ISO8601.date(startISO) else {
                throw ImportError.invalidDay(startISO)
            }
            let day = Self.day(in: startISO, fallbackDate: startDate)
            let model = row[cModel].trimmingCharacters(in: .whitespaces)
            let costString = row[cCost].trimmingCharacters(in: .whitespaces)
            let currency = row[cCurrency].trimmingCharacters(in: .whitespaces)
            guard let amount = Decimal(string: costString, locale: Locale(identifier: "en_US_POSIX")) else {
                throw ImportError.unsupportedSchema(details: "unparseable cost value '" + costString + "' in cost file")
            }
            records.append(UsageRecord(
                timestamp: startDate,
                day: day,
                apiKeyFingerprint: nil,
                model: model,
                requestCount: nil,
                cacheHitTokens: nil,
                cacheMissTokens: nil,
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: nil,
                amount: amount,
                currency: currency,
                source: .officialCSV,
                verification: .official
            ))
        }
        records.sort { $0.day.value < $1.day.value }
        return CSVMapping(records: records, keyNames: [], priceRules: [])
    }

    /// Billing day = the date part of the timestamp in the timestamp's own offset.
    static func day(in isoString: String, fallbackDate: Date) -> LocalDay {
        let prefix = String(isoString.prefix(10)).replacingOccurrences(of: "/", with: "-")
        if let day = LocalDay(prefix) { return day }
        return LocalDay(date: fallbackDate, timeZone: .autoupdatingCurrent)
    }
}
