import SwiftUI

/// Full dashboard (spec 35/36). Data comes exclusively from view models.
struct DashboardView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(spacing: 10) {
                MetricCard(
                    title: "Balance",
                    value: balanceValue,
                    subtitle: balanceSubtitle,
                    icon: "yensign.circle"
                )
                MetricCard(
                    title: "Today",
                    value: todayValue,
                    subtitle: todaySubtitle,
                    icon: "sun.max",
                    tint: .orange
                )
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

            UsageChart(daily: state.dashboardViewModel.summary?.daily ?? [])

            DailyUsageList(daily: state.dashboardViewModel.summary?.daily ?? []) { day in
                state.selectedDay = day
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 540)
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("API Meter").font(.title2.weight(.semibold))
                Text(updatedText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
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
        if let date = state.balanceViewModel.balance?.fetchedAt {
            return "Balance updated " + date.formatted(date: .omitted, time: .shortened)
        }
        return "No balance yet"
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
        state.dashboardViewModel.today?.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—"
    }

    private var todaySubtitle: String {
        let requests = state.dashboardViewModel.today?.requests.map { String($0) + " requests" } ?? ""
        let tokens = state.dashboardViewModel.today?.tokens.map { TokenFormatter.compact($0) + " tokens" } ?? ""
        if requests.isEmpty && tokens.isEmpty { return "no data yet" }
        return [requests, tokens].filter { !$0.isEmpty }.joined(separator: " · ")
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
