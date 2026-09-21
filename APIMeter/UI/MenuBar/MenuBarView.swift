import SwiftUI

/// Quick panel (spec 33): DeepSeek balance/today in one row, the coding
/// plan rings (ZCode + Kimi), then dashboard entry - nothing more.
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

            DeepSeekSection(state: state)
            ZCodeQuotaSection(state: state)

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
}

/// DeepSeek glance in a single row: balance and today side by side, with
/// the last-updated stamp right-aligned.
struct DeepSeekSection: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("DeepSeek").font(.caption).foregroundStyle(.secondary)
                if state.balanceViewModel.lastError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help(state.balanceViewModel.lastError ?? "")
                }
            }
            HStack(alignment: .bottom, spacing: 22) {
                metric(
                    caption: "余额",
                    value: state.balanceViewModel.balance?.balanceInfos.first.map {
                        CurrencyFormatter.format($0.totalBalance, currency: $0.currency)
                    },
                    size: 27,
                    tint: .blue
                )
                metric(
                    caption: "今日",
                    value: state.dashboardViewModel.todayDisplayCost.map {
                        CurrencyFormatter.format($0, currency: "CNY")
                    },
                    size: 19
                )
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if let fetchedAt = state.balanceViewModel.balance?.fetchedAt {
                        Text("更新 " + fetchedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let requests = state.dashboardViewModel.today?.requests {
                        Text(String(requests) + " req")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metric(caption: String, value: String?, size: CGFloat = 19, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(caption).font(.caption2).foregroundStyle(.secondary)
            if let value {
                Text(value)
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("—")
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
    }
}

/// Coding-plan quotas in the quick panel: depleting rings for ZCode
/// (5-hour / weekly) and, when the Kimi CLI credential is detected, Kimi's
/// windows, with the remaining percentage in the center.
struct ZCodeQuotaSection: View {
    @Bindable var state: AppState

    private var showKimi: Bool {
        state.kimiQuotaViewModel.hasCredential || state.kimiQuotaViewModel.quota != nil
    }

    private var showQoder: Bool {
        state.qoderQuotaViewModel.hasCredential || state.qoderQuotaViewModel.quota != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Coding Plans").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let level = state.zcodeQuotaViewModel.quota?.planLevel {
                    Text("ZCode " + level.capitalized).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if state.zcodeQuotaViewModel.quota != nil || showKimi || showQoder {
                // Grid keeps the two ring columns aligned across rows even
                // when the label widths differ.
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    if let quota = state.zcodeQuotaViewModel.quota {
                        GridRow {
                            QuotaRingBlock(
                                window: quota.fiveHour,
                                title: "ZCode 5 小时",
                                subtitle: state.zcodeQuotaViewModel.resetsIn(quota.fiveHour).map { "◔ " + $0 }
                            )
                            QuotaRingBlock(
                                window: quota.weekly,
                                title: "ZCode 本周",
                                subtitle: quota.weekly?.resetsAt.map { "重置 " + Self.resetStamp($0) }
                            )
                        }
                    }
                    if showKimi {
                        GridRow {
                            QuotaRingBlock(
                                window: state.kimiQuotaViewModel.quota?.fiveHour,
                                title: "Kimi 5 小时",
                                subtitle: state.kimiQuotaViewModel.resetsIn(state.kimiQuotaViewModel.quota?.fiveHour).map { "◔ " + $0 }
                            )
                            QuotaRingBlock(
                                window: state.kimiQuotaViewModel.quota?.weekly,
                                title: "Kimi 本周",
                                subtitle: kimiWeeklySubtitle
                            )
                        }
                    }
                    if showQoder {
                        GridRow {
                            QuotaRingBlock(
                                window: state.qoderQuotaViewModel.quota?.monthly,
                                title: "Qoder 月度",
                                subtitle: qoderPersonalSubtitle
                            )
                            QuotaRingBlock(
                                window: state.qoderQuotaViewModel.quota?.orgMonthly,
                                title: "Qoder 组织",
                                subtitle: state.qoderQuotaViewModel.hasOrgPool
                                    ? state.qoderQuotaViewModel.quota?.orgMonthly?.resetsAt.map { "重置 " + Self.resetStamp($0) }
                                    : "组织池未开放"
                            )
                        }
                    }
                }
            } else if state.zcodeQuotaViewModel.hasStoredKey {
                Text("Loading...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Add a key in Settings → Coding Plans")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error = state.zcodeQuotaViewModel.lastError {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                    Text("ZCode: unable to refresh").font(.caption2)
                }
                .foregroundStyle(.orange)
                .help(error)
            }
            if let error = state.kimiQuotaViewModel.lastError {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                    Text("Kimi: 凭据失效，请运行 kimi login").font(.caption2)
                }
                .foregroundStyle(.orange)
                .help(error)
            }
        }
    }

    /// Compact weekly reset stamp, e.g. "周四 06:56" / "Thu 06:56".
    static func resetStamp(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var kimiWeeklySubtitle: String? {
        let kimi = state.kimiQuotaViewModel
        var parts: [String] = []
        if let level = kimi.quota?.planLevel {
            parts.append(level)
        }
        if let resetsAt = kimi.quota?.weekly?.resetsAt {
            parts.append("重置 " + Self.resetStamp(resetsAt))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var qoderPersonalSubtitle: String? {
        let qoder = state.qoderQuotaViewModel
        var parts: [String] = []
        if let remaining = qoder.quota?.monthly?.effectiveRemaining {
            parts.append("剩 " + QuotaWidgetCard.remainingText(remaining))
        }
        if let resetsAt = qoder.quota?.monthly?.resetsAt {
            parts.append("重置 " + Self.resetStamp(resetsAt))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

