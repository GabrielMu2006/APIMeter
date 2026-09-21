import SwiftUI

/// The desktop widget grid: two ZCode quota cards on top, the DeepSeek
/// balance card below. Pure display of view-model state - window behavior
/// lives in WidgetPanelController.
///
/// Interactions: drag anywhere (window-level), double-click a card opens the
/// dashboard, right-click for the actions menu. Click-through mode is a
/// controller concern (mouse events never reach the view).
struct DesktopWidgetsView: View {
    @Bindable var state: AppState

    private let cardWidth: CGFloat = 156
    private let cardHeight: CGFloat = 116
    private let wideCardHeight: CGFloat = 96
    private let spacing: CGFloat = 12

    var body: some View {
        // Periodic re-evaluation keeps the reset countdown ticking between
        // data refreshes without extra timers or network calls.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            grid(now: timeline.date)
        }
        .contextMenu {
            Button("打开主面板") { state.toggleDashboard() }
            Button(state.widgetPanelController?.isClickThrough == true ? "关闭鼠标穿透" : "鼠标穿透（纯展示）") {
                state.widgetPanelController?.toggleClickThrough()
            }
            Button("刷新") {
                state.widgetPanelController?.refreshNow()
            }
            Divider()
            Button("隐藏小组件") {
                state.environment.settings.showDesktopWidgets = false
                state.widgetPanelController?.hide()
            }
        }
        .onTapGesture {
            state.toggleDashboard()
        }
        .task {
            await state.refreshAll()
        }
    }

    private func grid(now: Date) -> some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                QuotaWidgetCard(
                    title: "5 小时窗口",
                    window: state.zcodeQuotaViewModel.quota?.fiveHour,
                    isFiveHourCard: true,
                    resetsIn: state.zcodeQuotaViewModel.resetsIn(state.zcodeQuotaViewModel.quota?.fiveHour, now: now)
                )
                .frame(width: cardWidth, height: cardHeight)
                QuotaWidgetCard(
                    title: "本周窗口",
                    window: state.zcodeQuotaViewModel.quota?.weekly,
                    isFiveHourCard: false,
                    planLevel: state.zcodeQuotaViewModel.quota?.planLevel
                )
                .frame(width: cardWidth, height: cardHeight)
            }
            if showKimiCard {
                HStack(spacing: spacing) {
                    QuotaWidgetCard(
                        title: "Kimi · 5 小时",
                        window: state.kimiQuotaViewModel.quota?.fiveHour,
                        isFiveHourCard: true,
                        resetsIn: state.kimiQuotaViewModel.resetsIn(state.kimiQuotaViewModel.quota?.fiveHour, now: now)
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    QuotaWidgetCard(
                        title: "Kimi · 本周",
                        window: state.kimiQuotaViewModel.quota?.weekly,
                        isFiveHourCard: false,
                        captionOverride: kimiWeeklyCaption
                    )
                    .frame(width: cardWidth, height: cardHeight)
                }
            }
            if showQoderRow {
                HStack(spacing: spacing) {
                    QuotaWidgetCard(
                        title: "Qoder · 月度",
                        window: state.qoderQuotaViewModel.quota?.monthly,
                        isFiveHourCard: false,
                        captionOverride: qoderPersonalCaption
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    QuotaWidgetCard(
                        title: "Qoder · 组织池",
                        window: state.qoderQuotaViewModel.quota?.orgMonthly,
                        isFiveHourCard: false,
                        captionOverride: state.qoderQuotaViewModel.hasOrgPool ? nil : "组织池未开放"
                    )
                    .frame(width: cardWidth, height: cardHeight)
                }
            }
            BalanceWidgetCard(
                balance: state.balanceViewModel.balance?.balanceInfos.first,
                todayCost: state.dashboardViewModel.todayDisplayCost,
                lastError: state.balanceViewModel.lastError
            )
            .frame(width: cardWidth * 2 + spacing, height: wideCardHeight)
        }
    }

    /// Kimi needs no configuration (credential auto-detected from the CLI),
    /// so its row shows whenever there is data or a usable credential.
    private var showKimiCard: Bool {
        state.kimiQuotaViewModel.hasCredential || state.kimiQuotaViewModel.quota != nil
    }

    /// Qoder likewise auto-detects from the desktop app's encrypted auth.
    private var showQoderRow: Bool {
        state.qoderQuotaViewModel.hasCredential || state.qoderQuotaViewModel.quota != nil
    }

    private var qoderPersonalCaption: String? {
        let qoder = state.qoderQuotaViewModel
        if qoder.quota == nil {
            switch qoder.credentialState {
            case .expired:
                return "凭据失效 · 重新登录 Qoder"
            default:
                return "打开 Qoder 桌面版以激活"
            }
        }
        var parts: [String] = []
        if let remaining = qoder.quota?.monthly?.effectiveRemaining {
            parts.append("剩 " + QuotaWidgetCard.remainingText(remaining))
        }
        if let resetsAt = qoder.quota?.monthly?.resetsAt {
            parts.append("重置 " + ZCodeQuotaSection.resetStamp(resetsAt))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Kimi's quota is ratio-based - captions show percentages, not the
    /// request-count integers from the envelope.
    private var kimiWeeklyCaption: String? {
        let kimi = state.kimiQuotaViewModel
        if kimi.quota == nil {
            switch kimi.credentialState {
            case .expired:
                return "凭据失效 · 运行 kimi login"
            default:
                return "运行一次 Kimi CLI 以激活"
            }
        }
        var parts: [String] = []
        if let level = kimi.quota?.planLevel {
            parts.append(level)
        }
        if let percent = kimi.quota?.weekly?.remainingPercent {
            parts.append("剩 " + QuotaWidgetCard.percentText(percent))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Shared look of a desktop widget card: deep navy -> teal gradient with
/// white content, in the style of system widget tiles.
struct WidgetCardBackground: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.16, blue: 0.32),
                Color(red: 0.10, green: 0.34, blue: 0.44),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Health-tier accent used by quota rings and numbers.
struct QuotaHealthColor {
    static func tint(_ health: QuotaHealth) -> Color {
        switch health {
        case .green: return Color(red: 0.35, green: 0.90, blue: 0.70)
        case .orange: return Color(red: 1.0, green: 0.76, blue: 0.34)
        case .red: return Color(red: 1.0, green: 0.45, blue: 0.42)
        case .unknown: return .white.opacity(0.85)
        }
    }
}
