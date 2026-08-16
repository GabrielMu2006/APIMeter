import Foundation

/// Token display formatting (spec §106): 928 / 8.4K / 1.2M / 114.8M.
public enum TokenFormatter {
    public static func compact(_ tokens: Int64) -> String {
        switch tokens {
        case ..<1_000:
            return "\(tokens)"
        case ..<1_000_000:
            return frac(Double(tokens) / 1_000, unit: "K")
        case ..<1_000_000_000:
            return frac(Double(tokens) / 1_000_000, unit: "M")
        default:
            return frac(Double(tokens) / 1_000_000_000, unit: "B")
        }
    }

    public static func full(_ tokens: Int64, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
    }

    private static func frac(_ value: Double, unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded >= 100 || rounded == rounded.rounded() {
            return String(format: "%.0f%@", value, unit)
        }
        return String(format: "%.1f%@", value, unit)
    }
}
