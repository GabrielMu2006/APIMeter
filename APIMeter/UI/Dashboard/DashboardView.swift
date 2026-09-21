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

            // Equal quarters: DeepSeek | ZCode | Kimi | Qoder, two stacked
            // cards each, so every provider owns the same footprint.
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) {
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
                }
                VStack(spacing: 10) {
                    ZCodeQuotaCard(
                        title: "ZCode · 5 小时",
                        window: state.zcodeQuotaViewModel.quota?.fiveHour,
                        subtitle: zcodeFiveHourSubtitle
                    )
                    ZCodeQuotaCard(
                        title: "ZCode · 本周",
                        window: state.zcodeQuotaViewModel.quota?.weekly,
                        subtitle: zcodeWeeklySubtitle
                    )
                }
                VStack(spacing: 10) {
                    ZCodeQuotaCard(
                        title: "Kimi · 5 小时",
                        window: state.kimiQuotaViewModel.quota?.fiveHour,
                        subtitle: kimiFiveHourSubtitle
                    )
                    ZCodeQuotaCard(
                        title: "Kimi · 本周",
                        window: state.kimiQuotaViewModel.quota?.weekly,
                        subtitle: kimiWeeklySubtitle
                    )
                }
                .opacity((state.kimiQuotaViewModel.hasCredential || state.kimiQuotaViewModel.quota != nil) ? 1 : 0.35)
                VStack(spacing: 10) {
                    ZCodeQuotaCard(
                        title: "Qoder · 月度",
                        window: state.qoderQuotaViewModel.quota?.monthly,
                        subtitle: qoderPersonalSubtitle
                    )
                    ZCodeQuotaCard(
                        title: "Qoder · 组织池",
                        window: state.qoderQuotaViewModel.quota?.orgMonthly,
                        subtitle: state.qoderQuotaViewModel.hasOrgPool
                            ? qoderOrgSubtitle
                            : "组织池未开放"
                    )
                }
                .opacity((state.qoderQuotaViewModel.hasCredential || state.qoderQuotaViewModel.quota != nil) ? 1 : 0.35)
            }

            HStack {
                DateRangePicker(viewModel: state.dashboardViewModel)
                Spacer()
                // Period stats live beside the filters now - the summary
                // row belongs to the three providers.
                Text(periodCost + (periodStatsSubtitle.isEmpty ? "" : " · " + periodStatsSubtitle))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("Period cost with requests and tokens for the selected range")
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
        .frame(minWidth: 940, minHeight: 680)
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
        if state.balanceViewModel.lastError != nil {
            return "Refresh failed · last good value"
        }
        return state.balanceViewModel.hasStoredKey ? "DeepSeek account" : "Add a key in Settings"
    }

    private var todayValue: String {
        state.dashboardViewModel.todayDisplayCost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—"
    }

    private var todaySubtitle: String {
        // Compact: source label only - requests/tokens live in the daily
        // list and the day detail; the updated time is in the header line.
        if state.dashboardViewModel.todayBalanceEstimate != nil {
            return "Balance-derived"
        }
        if let partial = state.dashboardViewModel.todayPartialEstimate {
            return "Since " + partial.since.formatted(date: .omitted, time: .shortened)
        }
        if state.dashboardViewModel.today != nil {
            return "Official export"
        }
        return "no data yet"
    }

    private var periodCost: String {
        state.dashboardViewModel.summary?.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—"
    }

    private var zcodeWeeklySubtitle: String {
        var parts: [String] = []
        if let level = state.zcodeQuotaViewModel.quota?.planLevel {
            parts.append(level.capitalized)
        }
        if let resetsAt = state.zcodeQuotaViewModel.quota?.weekly?.resetsAt {
            parts.append("重置 " + ZCodeQuotaSection.resetStamp(resetsAt))
        }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    private var zcodeFiveHourSubtitle: String {
        state.zcodeQuotaViewModel.resetsIn(state.zcodeQuotaViewModel.quota?.fiveHour)
            .map { "◔ " + $0 + " 后重置" } ?? ""
    }

    private var kimiFiveHourSubtitle: String {
        state.kimiQuotaViewModel.resetsIn(state.kimiQuotaViewModel.quota?.fiveHour)
            .map { "◔ " + $0 + " 后重置" } ?? ""
    }

    private var qoderPersonalSubtitle: String {
        let qoder = state.qoderQuotaViewModel
        if qoder.quota == nil {
            return qoder.hasCredential ? "Loading..." : "Open the Qoder app once"
        }
        var parts: [String] = []
        if let remaining = qoder.quota?.monthly?.effectiveRemaining {
            parts.append("剩 " + QuotaWidgetCard.remainingText(remaining) + " credits")
        }
        if let resetsAt = qoder.quota?.monthly?.resetsAt {
            parts.append("重置 " + ZCodeQuotaSection.resetStamp(resetsAt))
        }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    private var qoderOrgSubtitle: String {
        var parts: [String] = []
        if let remaining = state.qoderQuotaViewModel.quota?.orgMonthly?.effectiveRemaining {
            parts.append("剩 " + QuotaWidgetCard.remainingText(remaining) + " credits")
        }
        if let resetsAt = state.qoderQuotaViewModel.quota?.orgMonthly?.resetsAt {
            parts.append("重置 " + ZCodeQuotaSection.resetStamp(resetsAt))
        }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    private var kimiWeeklySubtitle: String {
        let kimi = state.kimiQuotaViewModel
        if kimi.quota == nil {
            return kimi.hasCredential ? "Loading..." : "Run the Kimi CLI once"
        }
        var parts: [String] = []
        if let level = kimi.quota?.planLevel {
            parts.append(level)
        }
        if let resetsAt = kimi.quota?.weekly?.resetsAt {
            parts.append("重置 " + ZCodeQuotaSection.resetStamp(resetsAt))
        }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    private var periodStatsSubtitle: String {
        // Requests and tokens for the selected range - shown compactly next
        // to the filters.
        var parts: [String] = []
        if let requests = state.dashboardViewModel.summary?.requests {
            parts.append(TokenFormatter.compact(requests) + " req")
        }
        if let tokens = state.dashboardViewModel.summary?.tokens {
            parts.append(TokenFormatter.compact(tokens) + " tok")
        }
        return parts.joined(separator: " · ")
    }
}

extension LocalDay: Identifiable {
    public var id: String { value }
}
