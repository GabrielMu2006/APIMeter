import SwiftUI

/// Per-key breakdown for the selected period (spec 36, third priority).
/// Costs are derived from the official export (price x amount) and
/// cross-checked against billing totals.
struct APIKeyBreakdownView: View {
    @Bindable var state: AppState

    private var entries: [APIKeyUsage] {
        let keys = state.dashboardViewModel.summary?.byAPIKey ?? []
        return keys.sorted {
            ($0.cost ?? -1) > ($1.cost ?? -1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("API Keys").font(.headline)
                Spacer()
                Text("cost / req / tokens")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if entries.isEmpty {
                VStack {
                    Spacer()
                    Text("No key data in this period.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { key in
                    HStack(spacing: 8) {
                        Text(displayName(for: key))
                            .lineLimit(1)
                        Spacer()
                        Text(key.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—")
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                        Text(key.requests.map { String($0) } ?? "—")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(key.tokens.map(TokenFormatter.compact) ?? "—")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                .listStyle(.inset)
            }
            Text("Per-key cost is derived from official price x amount rows.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func displayName(for usage: APIKeyUsage) -> String {
        if let key = state.dashboardViewModel.apiKeys.first(where: { $0.fingerprint == usage.fingerprint }) {
            return key.bestDisplayName
        }
        return KeyFingerprint.displayPrefix(usage.fingerprint, length: 8) + "..."
    }
}
