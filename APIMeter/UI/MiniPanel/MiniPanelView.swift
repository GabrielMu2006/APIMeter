import SwiftUI

/// Mini floating panel (spec 44/45): balance + today cost ONLY.
/// Drag to move, right-click for actions, double-click to expand.
struct MiniPanelView: View {
    @Bindable var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Balance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(balanceText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Divider().frame(height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(todayText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if let error = state.balanceViewModel.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(error)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 190, minHeight: 48)
        .apiMeterAppearance(state.environment.settings.appearance)
        .contextMenu {
            Button("Open Dashboard") { state.floatingPanelController?.setMini(false) }
            Button(state.floatingPanelController?.isPinned == true ? "Unpin" : "Pin") {
                state.floatingPanelController?.togglePin()
            }
            Divider()
            Button("Refresh") { state.floatingPanelController?.refreshNow() }
            Button("Settings...") { openSettings() }
            Divider()
            Button("Quit API Meter") { NSApp.terminate(nil) }
        }
        .task {
            await state.refreshAll()
        }
    }

    private var balanceText: String {
        state.balanceViewModel.balance?.balanceInfos.first.map {
            CurrencyFormatter.format($0.totalBalance, currency: $0.currency)
        } ?? "—"
    }

    private var todayText: String {
        state.dashboardViewModel.todayDisplayCost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "—"
    }
}
