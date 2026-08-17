import SwiftUI

/// Quick panel (spec 33): balance, today, 7-day mini trend, top keys,
/// refresh, open dashboard - nothing more.
struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("API Meter").font(.headline)
                Spacer()
                if state.balanceViewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await state.balanceViewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                }
            }

            BalanceSection(state: state)
            TodaySection(state: state)

            VStack(alignment: .leading, spacing: 4) {
                Text("Last 7 Days").font(.caption).foregroundStyle(.secondary)
                MiniTrendChart(daily: last7Days)
            }

            TopKeysSection(state: state)

            Divider()

            HStack {
                Button("Open Dashboard") {
                    state.toggleDashboard()
                }
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
        .apiMeterAppearance(state.environment.settings.appearance)
        .task {
            await state.refreshAll()
        }
    }

    private var last7Days: [DailyUsage] {
        let today = LocalDay(date: Date())
        let cutoff = today.adding(days: -6)
        return (state.dashboardViewModel.summary?.daily ?? []).filter { $0.day >= cutoff && $0.day <= today }
    }
}

struct BalanceSection: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Balance").font(.caption).foregroundStyle(.secondary)
            if let info = state.balanceViewModel.balance?.balanceInfos.first {
                Text(CurrencyFormatter.format(info.totalBalance, currency: info.currency))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let error = state.balanceViewModel.lastError {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                        Text("Unable to refresh").font(.caption2)
                    }
                    .foregroundStyle(.orange)
                    .help(error)
                }
                if let fetchedAt = state.balanceViewModel.balance?.fetchedAt {
                    Text("Last updated " + fetchedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("—").font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(state.balanceViewModel.hasStoredKey ? "Loading..." : "Add a key in Settings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TodaySection: View {
    @Bindable var state: AppState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                if let today = state.dashboardViewModel.today {
                    Text(today.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("—").font(.system(size: 20, weight: .semibold, design: .rounded))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Requests").font(.caption).foregroundStyle(.secondary)
                Text(state.dashboardViewModel.today?.requests.map(String.init) ?? "—")
                    .font(.callout)
                    .monospacedDigit()
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("Tokens").font(.caption).foregroundStyle(.secondary)
                Text(state.dashboardViewModel.today?.tokens.map(TokenFormatter.compact) ?? "—")
                    .font(.callout)
                    .monospacedDigit()
            }
        }
    }
}

struct TopKeysSection: View {
    @Bindable var state: AppState

    private var topKeys: [APIKeyUsage] {
        let keys = state.dashboardViewModel.summary?.byAPIKey ?? []
        return Array(keys.sorted { ($0.tokens ?? 0) > ($1.tokens ?? 0) }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top API Keys").font(.caption).foregroundStyle(.secondary)
            if topKeys.isEmpty {
                Text("No key data yet").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(topKeys) { key in
                    HStack {
                        Text(displayName(for: key))
                            .lineLimit(1)
                        Spacer()
                        Text(key.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(key.cost == nil ? .tertiary : .primary)
                        Text(key.tokens.map(TokenFormatter.compact) ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func displayName(for usage: APIKeyUsage) -> String {
        if let key = state.dashboardViewModel.apiKeys.first(where: { $0.fingerprint == usage.fingerprint }) {
            return key.bestDisplayName
        }
        return KeyFingerprint.displayPrefix(usage.fingerprint, length: 8) + "..."
    }
}
