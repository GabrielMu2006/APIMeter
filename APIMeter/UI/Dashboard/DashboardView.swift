import SwiftUI

/// Full dashboard (spec 35/36). Data comes exclusively from view models.
/// Layout: metric cards -> filters -> compact chart -> daily list + key
/// breakdown sharing the remaining space.
struct DashboardView: View {
    @Bindable var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 10) {
                MetricCard(
                    title: "Balance",
                    value: balanceValue,
                    subtitle: balanceSubtitle,
                    icon: "yensign.circle"
                )
                Button {
                    let now = LocalDay(date: Date())
                    if state.dashboardViewModel.summary?.daily.contains(where: { $0.day == now }) == true {
                        state.selectedDay = now
                    }
                } label: {
                    MetricCard(
                        title: "Today",
                        value: todayValue,
                        subtitle: todaySubtitle,
                        icon: "sun.max",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
                .help("Open today's detail")
                MetricCard(
                    title: "Period Cost",
                    value: periodCost,
                    subtitle: rangeSubtitle,
                    icon: "sum",
                    tint: .green
                )
                MetricCard(
                    title: "Requests",
                    value: state.dashboardViewModel.summary?.requests.map(String.init) ?? "—",
                    subtitle: "in selected period",
                    icon: "arrow.left.arrow.right",
                    tint: .blue
                )
                MetricCard(
                    title: "Tokens",
                    value: state.dashboardViewModel.summary?.tokens.map(TokenFormatter.compact) ?? "—",
                    subtitle: state.dashboardViewModel.summary?.tokens.map { TokenFormatter.full($0) } ?? "",
                    icon: "number",
                    tint: .purple
                )
            }

            HStack {
                DateRangePicker(viewModel: state.dashboardViewModel)
                APIKeyFilter(viewModel: state.dashboardViewModel)
            }

            UsageChart(
                daily: state.dashboardViewModel.dailyList,
                perKeyCosts: state.dashboardViewModel.perKeyCostsByDay.mapValues { entries in
                    entries.map { entry in
                        let name = state.dashboardViewModel.apiKeys
                            .first { $0.fingerprint == entry.fingerprint }?
                            .bestDisplayName ?? KeyFingerprint.displayPrefix(entry.fingerprint, length: 8)
                        return (name: name, cost: entry.cost)
                    }
                }
            )
            .frame(height: 150)

            HStack(alignment: .top, spacing: 12) {
                DailyUsageList(daily: state.dashboardViewModel.dailyList) { day in
                    state.selectedDay = day
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                APIKeyBreakdownView(state: state)
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 780, minHeight: 560)
        .apiMeterAppearance(state.environment.settings.appearance)
        .task {
            await state.refreshAll()
            // Verification aid: auto-open the latest day's detail sheet.
            if ProcessInfo.processInfo.environment["APIMETER_OPEN_DAY_DETAIL"] == "1" {
                state.selectedDay = state.dashboardViewModel.summary?.daily.map { $0.day }.max()
            }
        }
        .sheet(item: Binding(
            get: { state.selectedDay },
            set: { state.selectedDay = $0 }
        )) { day in
            DailyDetailView(state: state, day: day)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("API Meter").font(.title2.weight(.semibold))
                Text(updatedText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                state.floatingPanelController?.togglePin()
            } label: {
                Image(systemName: state.floatingPanelController?.isPinned == true ? "pin.fill" : "pin")
            }
            .help("Pin keeps the window floating above others")
            Button {
                state.floatingPanelController?.setMini(true)
            } label: {
                Image(systemName: "rectangle.compress.vertical")
            }
            .help("Switch to Mini mode")
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button {
                Task { await state.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(state.balanceViewModel.isLoading || state.dashboardViewModel.isLoading)
            .glassButtonStyle()
        }
    }

    private var updatedText: String {
        var parts: [String] = []
        if let date = state.balanceViewModel.balance?.fetchedAt {
            parts.append("Balance " + date.formatted(date: .omitted, time: .shortened))
        }
        if let reload = state.dashboardViewModel.lastReload {
            parts.append("Data " + reload.formatted(date: .omitted, time: .shortened))
        }
        return parts.isEmpty ? "No data yet" : parts.joined(separator: " · ")
    }

    private var balanceValue: String {
        state.balanceViewModel.balance?.balanceInfos.first.map { CurrencyFormatter.format($0.totalBalance, currency: $0.currency) } ?? "—"
    }

    private var balanceSubtitle: String {
        if let error = state.balanceViewModel.lastError {
            return "Unable to refresh - showing last good value"
        }
        return state.balanceViewModel.hasStoredKey ? "DeepSeek account" : "Add a key in Settings"
    }

    private var todayValue: String {
        state.dashboardViewModel.todayDisplayCost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—"
    }

    private var todaySubtitle: String {
        var parts: [String] = []
        parts.append(state.dashboardViewModel.todayDisplaySubtitle)
        if state.dashboardViewModel.todayBalanceEstimate != nil {
            if let fetchedAt = state.balanceViewModel.balance?.fetchedAt {
                parts.append("updated " + fetchedAt.formatted(date: .omitted, time: .shortened))
            }
        } else if let today = state.dashboardViewModel.today {
            var source = "Official export"
            if let imported = state.dashboardViewModel.latestImportAt {
                source += " · imported " + imported.formatted(date: .omitted, time: .shortened)
            }
            parts.append(source)
        } else {
            parts.append("no data yet")
        }
        if let today = state.dashboardViewModel.today {
            if let requests = today.requests { parts.append(String(requests) + " requests") }
            if let tokens = today.tokens { parts.append(TokenFormatter.compact(tokens) + " tokens") }
        }
        return parts.joined(separator: " · ")
    }

    private var periodCost: String {
        state.dashboardViewModel.summary?.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—"
    }

    private var rangeSubtitle: String {
        let (start, end) = state.dashboardViewModel.range
        return start.value + " .. " + end.value
    }
}

extension LocalDay: Identifiable {
    public var id: String { value }
}
