import Foundation

/// Categorized Kimi usage API errors.
public enum KimiError: Error, LocalizedError, Equatable {
    case authenticationFailed
    case rateLimited
    case serverError(status: Int)
    case invalidResponse(String)
    case network(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed: return "Kimi 凭据已失效，请运行 kimi login 重新登录"
        case .rateLimited: return "Kimi rate limited the request (429)."
        case .serverError(let status): return "Kimi server error (HTTP \(status))."
        case .invalidResponse(let reason): return "Unexpected Kimi response: \(reason)"
        case .network(let reason): return "Network error: \(reason)"
        }
    }
}

/// Raw shape of GET https://api.kimi.com/coding/v1/usages, confirmed from
/// the Kimi Code CLI's own traffic (community implementations ported the
/// menubar's KimiSubscriptionService). Defensive everywhere:
///
/// - numbers ship as JSON numbers AND strings (FlexibleDecimal/FlexibleInt)
/// - reset stamps ship as ISO-8601 or epoch seconds (FlexibleDate)
/// - the top-level `usage` envelope IS the weekly quota (its reset lands
///   ~7 days out); `limits[]` carries the shorter rate-limit windows
///   (window.duration + window.timeUnit, e.g. TIME_UNIT_MINUTE x 300 = the
///   5-hour window)
/// - `used` may be absent on rate-limit windows; derive it from
///   limit - remaining
struct KimiUsageResponse: Decodable {
    let usage: KimiUsageEnvelope?
    let limits: [KimiLimitEntry]?
    /// Officially named fine-grained ratios (0-1 floats) - the authoritative
    /// usage percentages when present.
    let usages: KimiUsageRatios?
    let user: KimiUser?
    let parallel: KimiParallel?

    struct KimiUsageEnvelope: Decodable {
        let limit: FlexibleDecimal?
        let remaining: FlexibleDecimal?
        let used: FlexibleDecimal?
        let resetTime: FlexibleDate?
    }

    struct KimiLimitEntry: Decodable {
        let window: KimiWindowSpec?
        let detail: KimiUsageEnvelope?
    }

    struct KimiWindowSpec: Decodable {
        let duration: FlexibleDecimal?
        let timeUnit: String?
    }

    struct KimiUsageRatios: Decodable {
        let limit_5h: KimiRatioEntry?
        let limit_7d: KimiRatioEntry?
    }

    struct KimiRatioEntry: Decodable {
        /// Usage fraction 0-1 (e.g. 0.000931 = 0.0931%).
        let used_ratio: FlexibleDecimal?
        let reset_time: FlexibleDate?
    }

    struct KimiUser: Decodable {
        let membership: KimiMembership?
    }

    struct KimiMembership: Decodable {
        let level: String?
    }

    struct KimiParallel: Decodable {
        let limit: FlexibleDecimal?
    }
}

/// Pure decoding of a Kimi usage response into the shared quota domain
/// model (the same QuotaWindow/CodingPlanQuota the ZCode provider uses).
/// Maps: top-level usage -> weekly window; the 5-hour entry from limits[];
/// other (short) rate-limit windows are ignored for display.
enum KimiQuotaDecoder {

    static func decode(data: Data) throws -> CodingPlanQuota {
        let raw: KimiUsageResponse
        do {
            raw = try JSONDecoder().decode(KimiUsageResponse.self, from: data)
        } catch {
            throw KimiError.invalidResponse("unparseable JSON")
        }
        return try map(raw)
    }

    static func map(_ raw: KimiUsageResponse) throws -> CodingPlanQuota {
        // 5-hour window: prefer the official ratio entry, enrich with the
        // integers from limits[] (request counts) when available.
        let fiveHourEnvelope = (raw.limits ?? []).first(where: { Self.isFiveHour($0.window) })?.detail
        let fiveHour = Self.window(
            from: fiveHourEnvelope,
            kind: .fiveHour,
            ratio: raw.usages?.limit_5h
        )
        // Weekly: top-level usage envelope + the 7d ratio entry.
        let weekly = Self.window(
            from: raw.usage,
            kind: .weekly,
            ratio: raw.usages?.limit_7d
        )
        var windows: [QuotaWindow] = []
        if let weekly {
            windows.append(weekly)
        }
        if let fiveHour, !windows.contains(where: { $0.kind == .fiveHour }) {
            windows.append(fiveHour)
        }
        guard !windows.isEmpty else {
            throw KimiError.invalidResponse("no usable quota windows in response")
        }
        return CodingPlanQuota(
            planLevel: raw.user?.membership?.level.map(Self.normalizeLevel),
            windows: windows,
            fetchedAt: Date()
        )
    }

    /// "LEVEL_INTERMEDIATE" -> "Intermediate"; unknown values pass through
    /// title-cased.
    static func normalizeLevel(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "LEVEL_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        return stripped.split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    static func isFiveHour(_ spec: KimiUsageResponse.KimiWindowSpec?) -> Bool {
        guard let spec, let duration = spec.duration?.wrappedValue else { return false }
        let unit = (spec.timeUnit ?? "").lowercased()
            .replacingOccurrences(of: "^time_unit_", with: "", options: .regularExpression)
            .replacingOccurrences(of: "s$", with: "", options: .regularExpression)
        switch unit {
        case "minute": return duration == 300
        case "hour": return duration == 5
        default: return false
        }
    }

    private static func window(from envelope: KimiUsageResponse.KimiUsageEnvelope?, kind: QuotaWindowKind, ratio: KimiUsageResponse.KimiRatioEntry?) -> QuotaWindow? {
        guard let envelope else {
            // Ratio-only responses (no envelope) still carry a usable window.
            guard let ratioPercent = ratio?.used_ratio?.wrappedValue else { return nil }
            return QuotaWindow(
                kind: kind,
                usedPercent: ratioPercent * 100,
                usedValue: nil,
                totalValue: nil,
                remaining: nil,
                resetsAt: ratio?.reset_time?.wrappedValue,
                modelDetails: []
            )
        }
        let limit = envelope.limit?.wrappedValue
        let remaining = envelope.remaining?.wrappedValue
        let used = envelope.used?.wrappedValue
            ?? limit.flatMap { l in remaining.map { Swift.max(0, l - $0) } }
        guard let limit, limit > 0 else { return nil }
        // The official ratio (fine-grained float) wins over integer math.
        let percent: Decimal? = ratio?.used_ratio?.wrappedValue.map { $0 * 100 }
            ?? used.map { Swift.min(100, ($0 / limit) * 100) }
        let resetsAt = ratio?.reset_time?.wrappedValue ?? envelope.resetTime?.wrappedValue
        return QuotaWindow(
            kind: kind,
            usedPercent: percent,
            usedValue: used,
            totalValue: limit,
            remaining: remaining,
            resetsAt: resetsAt,
            modelDetails: []
        )
    }
}
