import SwiftUI

/// One day's detail (spec 42): totals + per-key breakdown.
/// V1 does not expand the model dimension.
struct DailyDetailView: View {
    @Bindable var state: AppState
    let day: LocalDay
    @State private var summary: UsageSummary?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 16) {
            Text(day.value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()

            HStack(spacing: 10) {
                MetricCard(
                    title: "Total Cost",
                    value: summary?.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—",
                    subtitle: "from official export",
                    icon: "yensign.circle"
                )
                MetricCard(
                    title: "Requests",
                    value: summary?.requests.map(String.init) ?? "—",
                    subtitle: "in this day",
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
                Text("Per-key cost is derived from the official export (price x amount) and cross-checked against the billing totals.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .task {
            guard !loaded else { return }
            loaded = true
            summary = await state.dashboardViewModel.dayDetail(day)
        }
    }

    private func displayName(for usage: APIKeyUsage) -> String {
        if let key = state.dashboardViewModel.apiKeys.first(where: { $0.fingerprint == usage.fingerprint }) {
            return key.bestDisplayName
        }
        if usage.fingerprint == "(unknown)" { return "Account-level cost" }
        return KeyFingerprint.displayPrefix(usage.fingerprint, length: 8) + "..."
    }
}
