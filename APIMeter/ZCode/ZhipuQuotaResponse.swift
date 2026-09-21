import Foundation

/// Categorized ZCode/BigModel quota API errors.
public enum ZCodeError: Error, LocalizedError, Equatable {
    case authenticationFailed
    case rateLimited
    case serverError(status: Int)
    case invalidResponse(String)
    case network(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed: return "Coding Plan key was rejected (expired or incorrect)."
        case .rateLimited: return "Z.ai/BigModel rate limited the quota request (429)."
        case .serverError(let status): return "Z.ai/BigModel server error (HTTP \(status))."
        case .invalidResponse(let reason): return "Unexpected quota response: \(reason)"
        case .network(let reason): return "Network error: \(reason)"
        }
    }
}

/// Raw shape of GET /api/monitor/usage/quota/limit, cross-confirmed from the
/// official glm-plan-usage plugin and community implementations (codeburn,
/// oh-my-pi). Not an officially documented API - every field is defensive:
///
/// - numbers arrive sometimes as JSON numbers, sometimes as strings
///   (FlexibleDecimal / FlexibleInt)
/// - `usage` is the TOTAL allowance, `currentValue` is the USED amount
///   (counterintuitive naming kept from the wire format)
/// - `nextResetTime` arrives as epoch seconds, epoch milliseconds or an
///   ISO-8601 string
/// - the window identity is the (unit, number) pair: (3, 5) = 5-hour,
///   (6, 1) = weekly
/// - an auth failure can arrive as HTTP 200 with body-level code 401/403 -
///   that body code is the ONLY reliable expiry signal
struct ZhipuQuotaResponse: Decodable {
    let success: Bool?
    let code: FlexibleInt?
    let msg: String?
    let data: DataPayload?

    struct DataPayload: Decodable {
        let level: String?
        let limits: [LimitItem]?
    }

    struct LimitItem: Decodable {
        let type: String?
        let usage: FlexibleDecimal?
        let currentValue: FlexibleDecimal?
        let percentage: FlexibleDecimal?
        let remaining: FlexibleDecimal?
        let nextResetTime: FlexibleDate?
        let unit: FlexibleInt?
        let number: FlexibleInt?
        let usageDetails: [UsageDetail]?
    }

    struct UsageDetail: Decodable {
        let modelCode: String?
        let usage: FlexibleDecimal?
    }
}

/// Accepts a JSON number or a numeric string ("30", 30, "1.5", 1.5).
@propertyWrapper
struct FlexibleDecimal: Decodable, Equatable {
    let wrappedValue: Decimal?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Decimal.self) {
            wrappedValue = value
        } else if let raw = try? container.decode(String.self) {
            wrappedValue = Decimal(string: raw.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX"))
        } else if container.decodeNil() {
            wrappedValue = nil
        } else {
            wrappedValue = nil
        }
    }

    init(_ value: Decimal?) {
        self.wrappedValue = value
    }
}

/// Accepts a JSON number or a numeric string, as Int.
@propertyWrapper
struct FlexibleInt: Decodable, Equatable {
    let wrappedValue: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            wrappedValue = value
        } else if let raw = try? container.decode(String.self),
                  let parsed = Int(raw.trimmingCharacters(in: .whitespaces)) {
            wrappedValue = parsed
        } else {
            wrappedValue = nil
        }
    }

    init(_ value: Int?) {
        self.wrappedValue = value
    }
}

/// Accepts epoch seconds, epoch milliseconds, or an ISO-8601 string.
/// The three forms have all been observed in the wild.
@propertyWrapper
struct FlexibleDate: Decodable, Equatable {
    let wrappedValue: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            // Values above ~2001-09-09 in seconds are unambiguous milliseconds.
            wrappedValue = seconds > 1_000_000_000_000
                ? Date(timeIntervalSince1970: seconds / 1000)
                : Date(timeIntervalSince1970: seconds)
        } else if let raw = try? container.decode(String.self) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let seconds = Double(trimmed) {
                wrappedValue = seconds > 1_000_000_000_000
                    ? Date(timeIntervalSince1970: seconds / 1000)
                    : Date(timeIntervalSince1970: seconds)
            } else {
                wrappedValue = Self.parseISO(trimmed)
            }
        } else {
            wrappedValue = nil
        }
    }

    private static func parseISO(_ string: String) -> Date? {
        if let date = ISO8601.date(string) { return date }
        // Tolerate fractional seconds / offsets the strict style rejects.
        let styles: [Date.ISO8601FormatStyle] = [
            .init(includingFractionalSeconds: true),
            .init(),
        ]
        for style in styles {
            if let date = try? Date(string, strategy: style) { return date }
        }
        return nil
    }

    init(_ value: Date?) {
        self.wrappedValue = value
    }
}

/// Pure decoding of a quota response body into the domain model.
/// Throws ZCodeError.authenticationFailed when the body carries a 401/403
/// business code (possible even on HTTP 200), and invalidResponse when no
/// usable window can be decoded.
enum ZhipuQuotaDecoder {

    static func decode(data: Data) throws -> CodingPlanQuota {
        let raw: ZhipuQuotaResponse
        do {
            raw = try JSONDecoder().decode(ZhipuQuotaResponse.self, from: data)
        } catch {
            throw ZCodeError.invalidResponse("unparseable JSON")
        }
        return try map(raw)
    }

    static func map(_ raw: ZhipuQuotaResponse) throws -> CodingPlanQuota {
        if let code = raw.code?.wrappedValue, code == 401 || code == 403 {
            throw ZCodeError.authenticationFailed
        }
        guard raw.success ?? true else {
            throw ZCodeError.invalidResponse(raw.msg ?? "success == false")
        }
        let payload = raw.data
        var windows: [QuotaWindow] = []
        for item in payload?.limits ?? [] {
            guard let window = Self.window(from: item) else { continue }
            if !windows.contains(where: { $0.kind == window.kind }) {
                windows.append(window)
            }
        }
        guard !windows.isEmpty else {
            throw ZCodeError.invalidResponse("no usable quota windows in response")
        }
        return CodingPlanQuota(
            planLevel: payload?.level?.nilIfEmpty,
            windows: windows,
            fetchedAt: Date()
        )
    }

    private static func window(from item: ZhipuQuotaResponse.LimitItem) -> QuotaWindow? {
        let kind = Self.kind(type: item.type, unit: item.unit?.wrappedValue, number: item.number?.wrappedValue)
        guard let kind else { return nil }
        var percent = item.percentage?.wrappedValue
        if percent == nil,
           let used = item.currentValue?.wrappedValue,
           let total = item.usage?.wrappedValue,
           total > 0 {
            percent = (used / total) * 100
        }
        let details = (item.usageDetails ?? []).compactMap { detail -> QuotaModelDetail? in
            guard let code = detail.modelCode?.nilIfEmpty else { return nil }
            return QuotaModelDetail(modelCode: code, usage: detail.usage?.wrappedValue ?? 0)
        }
        return QuotaWindow(
            kind: kind,
            usedPercent: percent,
            usedValue: item.currentValue?.wrappedValue,
            totalValue: item.usage?.wrappedValue,
            remaining: item.remaining?.wrappedValue,
            resetsAt: item.nextResetTime?.wrappedValue,
            modelDetails: details
        )
    }

    /// The (unit, number) pair encodes the metering window; the `type` field
    /// distinguishes token/credit limits from the monthly tool (MCP) limit.
    static func kind(type: String?, unit: Int?, number: Int?) -> QuotaWindowKind? {
        if type == "TIME_LIMIT" { return .monthlyTool }
        if unit == 3, number == 5 { return .fiveHour }
        if unit == 6, number == 1 { return .weekly }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
