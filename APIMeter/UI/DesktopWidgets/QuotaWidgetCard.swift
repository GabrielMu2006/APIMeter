import SwiftUI

/// One quota card: a large circular ring showing the REMAINING percentage
/// in the center (the ring depletes as the window is spent), with the reset
/// countdown / plan tier and the remaining amount as the caption. Health
/// tint is still driven by the USED share (>=90% used = red).
struct QuotaWidgetCard: View {
    let title: String
    let window: QuotaWindow?
    var isFiveHourCard: Bool = true
    var resetsIn: String?
    var planLevel: String?
    /// Overrides the computed caption (used by providers whose sub-line
    /// combines info from more than one window, e.g. Kimi).
    var captionOverride: String? = nil

    var body: some View {
        ZStack {
            WidgetCardBackground()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 0)
            if let window {
                QuotaRing(window: window, lineWidth: 7, percentFont: 15, palette: .widget)
                    .frame(width: 64, height: 64)
            } else {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 7)
                    Text("—")
                        .font(.system(size: 14, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(width: 64, height: 64)
            }
            Spacer(minLength: 0)
            if let window {
                Text(captionOverride ?? caption(for: window))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let captionOverride {
                Text(captionOverride)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("在 设置 → ZCode 添加 Key")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(10)
    }

    private func caption(for window: QuotaWindow) -> String {
        var parts: [String] = []
        if isFiveHourCard {
            if let resetsIn {
                parts.append("◔ " + resetsIn)
            }
        } else {
            if let planLevel {
                parts.append(planLevel)
            }
            // Weekly windows: show when the next reset lands.
            if let resetsAt = window.resetsAt {
                parts.append("重置 " + ZCodeQuotaSection.resetStamp(resetsAt))
            }
        }
        if let remaining = window.effectiveRemaining {
            parts.append("剩 " + Self.compact(remaining))
        }
        return parts.joined(separator: " · ")
    }

    /// "34%" with the percent sign as-is; used for the remaining share.
    static func percentText(_ percent: Decimal) -> String {
        let rounded = NSDecimalNumber(decimal: percent).rounding(accordingToBehavior: nil)
        return String(describing: rounded.intValue) + "%"
    }

    /// Remaining amount: integral values drop the fraction ("680"),
    /// fractional keep one decimal ("42.5").
    static func remainingText(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        if number == number.rounding(accordingToBehavior: nil) {
            return String(describing: number.intValue)
        }
        return String(format: "%.1f", number.doubleValue)
    }

    /// Compact integer amounts for captions (1234 -> 1.2k).
    static func compact(_ value: Decimal) -> String {
        TokenFormatter.compact(NSDecimalNumber(decimal: value).int64Value)
    }
}
