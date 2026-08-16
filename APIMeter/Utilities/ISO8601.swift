import Foundation

/// UTC ISO8601 storage helpers. Database timestamps are always UTC (spec §107).
/// Uses Swift value-type format styles (Sendable-safe).
public enum ISO8601 {
    private static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    private static let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public static func string(_ date: Date) -> String {
        date.formatted(style)
    }

    /// Fractional-second form for canonicalization (row hashes). Two requests
    /// in the same second are distinct rows and must not collapse.
    public static func fractionalString(_ date: Date) -> String {
        date.formatted(fractionalStyle)
    }

    public static func date(_ string: String) -> Date? {
        try? Date(string, strategy: style)
    }
}
