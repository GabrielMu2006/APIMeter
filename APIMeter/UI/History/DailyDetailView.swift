import SwiftUI

/// One day's detail (spec 42): totals + per-key breakdown.
/// TODAY is special: the headline cost is the balance-derived estimate
/// (live, cannot be split per key); the per-key breakdown below comes
/// from the latest official export and is stamped with its import time.
struct DailyDetailView: View {
    @Bindable var state: AppState
    let day: LocalDay
    @State private var summary: UsageSummary?
    @State private var loaded = false

    private var isToday: Bool {
        day == LocalDay(date: Date())
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(day.value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Button {
                    state.closeDayDetail()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)   // Esc also closes
                .help("Close (Esc)")
            }

            HStack(spacing: 10) {
                MetricCard(
                    title: "Total Cost",
                    value: headlineCost,
                    subtitle: headlineSubtitle,
                    icon: "yensign.circle"
                )
                MetricCard(
                    title: "Requests",
                    value: summary?.requests.map(String.init) ?? "—",
                    subtitle: isToday ? "as of last export" : "in this day",
                    icon: "arrow.left.arrow.right"
                )
                MetricCard(
                    title: "Tokens",
                    value: summary?.tokens.map(TokenFormatter.compact) ?? "—",
                    subtitle: summary?.tokens.map { TokenFormatter.full($0) + " total" } ?? "",
                    icon: "number"
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("API Keys").font(.headline)
                let keys = summary?.byAPIKey ?? []
                if keys.isEmpty {
                    Text("No per-key data for this day.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    List(keys) { key in
                        HStack {
                            Text(displayName(for: key))
                            Spacer()
                            Text(key.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—")
                                .monospacedDigit()
                                .frame(width: 90, alignment: .trailing)
                            Text(key.requests.map { String($0) + " req" } ?? "—")
                                .monospacedDigit()
                                .frame(width: 90, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            Text(key.tokens.map(TokenFormatter.compact) ?? "—")
                                .monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.inset)
                }
                if isToday {
                    Text("Today's live total is balance-derived and cannot be split per key. The per-key breakdown above comes from the latest official export" + importStamp + ".")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Per-key cost is derived from the official export (price x amount) and cross-checked against the billing totals.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 480)
        .task {
            guard !loaded else { return }
            loaded = true
            summary = await state.dashboardViewModel.dayDetail(day)
        }
    }

    private var headlineCost: String {
        if isToday, let estimate = state.dashboardViewModel.todayBalanceEstimate {
            return CurrencyFormatter.format(estimate.amount, currency: "CNY")
        }
        return summary?.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—"
    }

    private var headlineSubtitle: String {
        if isToday {
            if state.dashboardViewModel.todayBalanceEstimate != nil {
                return "balance-derived (live)"
            }
            return "official export" + importStamp
        }
        return "from official export"
    }

    private var importStamp: String {
        if let imported = state.dashboardViewModel.latestImportAt {
            return " (imported " + imported.formatted(date: .omitted, time: .shortened) + ")"
        }
        return ""
    }

    private func displayName(for usage: APIKeyUsage) -> String {
        if let key = state.dashboardViewModel.apiKeys.first(where: { $0.fingerprint == usage.fingerprint }) {
            return key.bestDisplayName
        }
        if usage.fingerprint == "(unknown)" { return "Account-level cost" }
        return KeyFingerprint.displayPrefix(usage.fingerprint, length: 8) + "..."
    }
}
