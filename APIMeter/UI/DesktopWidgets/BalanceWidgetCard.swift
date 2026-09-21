import SwiftUI

/// The wide bottom card: DeepSeek balance AND today's spend - the two
/// numbers the desktop widget needs at a glance - on the navy gradient.
struct BalanceWidgetCard: View {
    let balance: BalanceInfo?
    let todayCost: Decimal?
    let lastError: String?

    var body: some View {
        ZStack {
            WidgetCardBackground()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("DeepSeek")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        if lastError != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                                .help("Unable to refresh - showing last good value")
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 24) {
                        metric(
                            value: balance.map { CurrencyFormatter.format($0.totalBalance, currency: $0.currency) },
                            caption: "余额"
                        )
                        metric(
                            value: todayCost.map { CurrencyFormatter.format($0, currency: "CNY") },
                            caption: "今日消费"
                        )
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func metric(value: String?, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let value {
                Text(value)
                    .font(.system(size: 26, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("—")
                    .font(.system(size: 26, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
