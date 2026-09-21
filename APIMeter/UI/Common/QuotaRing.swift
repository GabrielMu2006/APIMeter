import SwiftUI

/// Circular ring showing the REMAINING share of a quota window; the ring
/// depletes as the window is spent (battery metaphor), with the remaining
/// percentage in the center. Shared by the desktop widget cards and the
/// menu bar quick panel.
///
/// Two palettes: `.widget` (light strokes for the navy gradient cards) and
/// `.system` (standard semantic colors for light/dark app surfaces).
struct QuotaRing: View {
    enum Palette {
        case widget
        case system

        func color(for health: QuotaHealth) -> Color {
            switch self {
            case .widget: return QuotaHealthColor.tint(health)
            case .system:
                switch health {
                case .green: return .green
                case .orange: return .orange
                case .red: return .red
                case .unknown: return .secondary
                }
            }
        }
    }

    let window: QuotaWindow?
    var lineWidth: CGFloat = 7
    var percentFont: CGFloat = 14
    var palette: Palette = .widget

    var body: some View {
        let usedDouble = NSDecimalNumber(decimal: window?.usedPercent ?? 0).doubleValue
        let fraction = min(max(1 - usedDouble / 100.0, 0), 1)
        let color = palette.color(for: window?.health ?? .unknown)
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let percent = window?.remainingPercent {
                VStack(spacing: -2) {
                    Text(QuotaWidgetCard.percentText(percent))
                        .font(.system(size: percentFont, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 2)
                    Text("剩")
                        .font(.system(size: max(percentFont - 8, 7)))
                        .opacity(0.65)
                }
                .foregroundStyle(palette == .widget ? .white : .primary)
            } else {
                Text("—")
                    .font(.system(size: percentFont, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(palette == .widget ? Color.white.opacity(0.5) : Color.secondary)
            }
        }
    }
}

/// A ring plus its label column - the shared building block of the menu bar
/// quick panel and the dashboard quota strip.
struct QuotaRingBlock: View {
    let window: QuotaWindow?
    let title: String
    var subtitle: String? = nil
    var palette: QuotaRing.Palette = .system
    var ringSize: CGFloat = 40
    var lineWidth: CGFloat = 4.5
    var percentFont: CGFloat = 11

    var body: some View {
        HStack(spacing: 7) {
            QuotaRing(window: window, lineWidth: lineWidth, percentFont: percentFont, palette: palette)
                .frame(width: ringSize, height: ringSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if let remaining = window?.effectiveRemaining {
                    Text("剩 " + QuotaWidgetCard.remainingText(remaining))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .help(title + "窗口 · 剩余 "
            + (window?.remainingPercent.map(QuotaWidgetCard.percentText) ?? "?")
            + (window?.effectiveRemaining.map { "（" + QuotaWidgetCard.remainingText($0) + "）" } ?? "")
            + (window?.resetsAt.map { " · 重置 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""))
    }
}
