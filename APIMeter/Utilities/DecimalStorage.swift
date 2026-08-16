import Foundation

/// Locale-independent storage helpers for money as TEXT in SQLite (spec §105:
/// amounts are Decimal, never Double; TEXT keeps exactness for SUM-free storage).
public enum DecimalStorage {
    public static func string(_ value: Decimal) -> String {
        value.description
    }

    public static func decimal(_ string: String) -> Decimal? {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }
}
