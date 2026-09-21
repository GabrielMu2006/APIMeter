import SwiftUI

/// ZCode quota as a dashboard metric card: depleting ring + remaining
/// percentage, mirroring the DeepSeek MetricCard look so both providers
/// share the summary row with equal visual weight.
struct ZCodeQuotaCard: View {
    let title: String
    let window: QuotaWindow?
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption)
                    .foregroundStyle(.teal)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                QuotaRing(window: window, lineWidth: 5, percentFont: 11, palette: .system)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    if let percent = window?.remainingPercent {
                        Text("剩 " + QuotaWidgetCard.percentText(percent))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("—")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if window == nil && !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else {
                        Text(window == nil ? "Set key in Settings → Coding Plans" : subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
