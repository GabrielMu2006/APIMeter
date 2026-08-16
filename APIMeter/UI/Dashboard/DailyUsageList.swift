import SwiftUI

/// Daily history rows (spec 41). Tap opens the day detail (spec 42).
struct DailyUsageList: View {
    let daily: [DailyUsage]
    let onSelect: (LocalDay) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daily Usage").font(.headline)
            if daily.isEmpty {
                Text("No usage data in this period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(daily.sorted { $0.day > $1.day }) { day in
                        Button {
                            onSelect(day.day)
                        } label: {
                            HStack {
                                Text(day.day.value)
                                    .monospacedDigit()
                                Spacer()
                                Text(day.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—")
                                    .monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                                Text(day.requests.map { String($0) + " req" } ?? "—")
                                    .monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                Text(day.tokens.map(TokenFormatter.compact) ?? "—")
                                    .monospacedDigit()
                                    .frame(width: 80, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                if day.verification == .official {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                        .help("Verified against official DeepSeek export")
                                } else {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.secondary)
                                        .help("Estimated (local gateway)")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}
