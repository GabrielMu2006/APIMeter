import Foundation

public enum CurrencyFormatter {
    public static func format(_ amount: Decimal, currency: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currency)"
    }

    public static func formatCompact(_ amount: Decimal, currency: String, locale: Locale = .current) -> String {
        format(amount, currency: currency, locale: locale)
    }
}
