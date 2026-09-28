import SwiftUI

/// Shared widget chrome: the same deep-navy -> teal gradient the in-app
/// desktop widget cards use.
private let widgetGradient = LinearGradient(
    colors: [
        Color(red: 0.08, green: 0.16, blue: 0.32),
        Color(red: 0.10, green: 0.34, blue: 0.44),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// Traffic-light tint by remaining percent (70% / 90% used thresholds -
/// mirrors the app's QuotaHealth).
private func healthTint(remaining: Double?) -> Color {
    guard let remaining else { return .white.opacity(0.25) }
    let used = 100 - remaining
    if used >= 90 { return Color(red: 1.0, green: 0.45, blue: 0.42) }
    if used >= 70 { return Color(red: 1.0, green: 0.76, blue: 0.34) }
    return Color(red: 0.35, green: 0.90, blue: 0.70)
}

private func moneyText(_ amount: Decimal, _ currency: String, size: CGFloat, weight: Font.Weight) -> Text {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency.uppercased()
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let string = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currency)"
    return Text(string)
        .font(.system(size: size, weight: weight, design: .rounded))
        .monospacedDigit()
        .foregroundColor(.white)
}

private struct QuotaRingView: View {
    let remaining: Double?
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: lineWidth)
            if let remaining, remaining > 0 {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, remaining / 100)))
                    .stroke(healthTint(remaining: remaining), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

// MARK: - Medium (rings-only grid)

/// One provider cell of the medium widget: name, two rings (5h + weekly, or
/// Qoder's monthly pair) and the 5-hour reset countdown.
private struct ProviderCell: View {
    let provider: WidgetSnapshot.ProviderInfo
    let windows: [WidgetSnapshot.WindowInfo]
    let now: Date

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                ring(window)
            }
            if windows.isEmpty {
                QuotaRingView(remaining: nil)
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text(provider.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if provider.offline {
                        Text("离线")
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
                subtitle
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }

    private func ring(_ window: WidgetSnapshot.WindowInfo) -> some View {
        QuotaRingView(remaining: window.remainingPercent)
            .frame(width: 24, height: 24)
            .overlay {
                if let remaining = window.remainingPercent {
                    Text("\(Int(remaining.rounded()))")
                        .font(.system(size: 7, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
    }

    private var subtitle: Text {
        let style = Font.system(size: 8.5)
        let color = Color.white.opacity(0.6)
        if !provider.available {
            return Text("未配置").font(style).foregroundColor(color)
        }
        if let fiveHour = windows.first(where: { $0.kind == "fiveHour" }), let resetsAt = fiveHour.resetsAt, resetsAt > now {
            // Live countdown: the system re-renders this text every second
            // without needing a new timeline entry.
            return Text(timerInterval: now...resetsAt, countsDown: true).font(style).foregroundColor(color)
        }
        if let weekly = windows.first(where: { $0.kind == "weekly" }), let resetsAt = weekly.resetsAt, resetsAt > now {
            return Text("周重置 ").font(style).foregroundColor(color)
                + Text(timerInterval: now...resetsAt, countsDown: true).font(style).foregroundColor(color)
        }
        return Text(provider.planLevel.map { $0.capitalized } ?? "—").font(style).foregroundColor(color)
    }
}

// MARK: - Large (balance header + one card per provider)

/// One window column of a large provider card: ring with the percentage
/// inside, remaining amount and reset info underneath.
private struct LargeWindowColumn: View {
    let window: WidgetSnapshot.WindowInfo
    let now: Date
    var caption: String = ""

    var body: some View {
        VStack(spacing: 2) {
            QuotaRingView(remaining: window.remainingPercent, lineWidth: 3.5)
                .frame(width: 38, height: 38)
                .overlay {
                    if let remaining = window.remainingPercent {
                        Text("\(Int(remaining.rounded()))%")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text("—")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            Text("剩 " + (window.remainingLabel ?? (window.remainingPercent.map { "\(Int($0.rounded()))%" } ?? "—")))
                .font(.system(size: 8.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            detail
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var detail: some View {
        let color = Color.white.opacity(0.55)
        if let resetsAt = window.resetsAt, resetsAt > now {
            if window.kind == "fiveHour" {
                // Live countdown, self-updating between timeline entries.
                Text(timerInterval: now...resetsAt, countsDown: true).font(.system(size: 8)).foregroundColor(color)
            } else {
                Text("重置 " + resetsAt.formatted(.dateTime.weekday(.narrow).hour().minute())).font(.system(size: 8)).foregroundColor(color)
            }
        } else if !caption.isEmpty {
            Text(caption).font(.system(size: 8)).foregroundColor(color)
        } else {
            Text(" ").font(.system(size: 8))
        }
    }
}

/// One provider card of the large widget: name (+ offline badge) and its
/// windows as ring columns. Qoder without an org pool gets a disabled
/// placeholder column, mirroring the in-app panel.
private struct LargeProviderBlock: View {
    let provider: WidgetSnapshot.ProviderInfo
    let windows: [WidgetSnapshot.WindowInfo]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(provider.displayName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if provider.offline {
                    Text("离线")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.orange)
                }
                if let plan = provider.planLevel {
                    Text(plan.capitalized)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if provider.available {
                HStack(alignment: .top, spacing: 8) {
                    displayColumns
                }
            } else {
                Text("未检测到凭据 - 打开 API Meter 配置")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var displayColumns: some View {
        ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
            LargeWindowColumn(
                window: window,
                now: now,
                caption: window.kind == "orgMonthly" ? "组织池" : ""
            )
        }
        if provider.id == "qoder", !windows.contains(where: { $0.kind == "orgMonthly" }) {
            LargeWindowColumn(
                window: WidgetSnapshot.WindowInfo(kind: "orgMonthly", remainingPercent: nil, remainingLabel: nil, resetsAt: nil),
                now: now,
                caption: "组织池未开放"
            )
        }
    }
}

private extension CodingPlansView {
    var largeLayout: some View {
        let providers = entry.snapshot.providers
        let rows = [Array(providers.prefix(2)), Array(providers.dropFirst(2).prefix(2))]
        return VStack(alignment: .leading, spacing: 7) {
            header
            ForEach(0..<rows.count, id: \.self) { index in
                HStack(spacing: 7) {
                    ForEach(rows[index]) { provider in
                        LargeProviderBlock(
                            provider: provider,
                            windows: entry.snapshot.windows(for: provider),
                            now: entry.date
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(1)
    }

    @ViewBuilder private var header: some View {
        if let balance = entry.snapshot.balance {
            HStack(alignment: .firstTextBaseline) {
                Text("DeepSeek 余额")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                moneyText(balance.total, balance.currency, size: 17, weight: .bold)
                Spacer()
                if let today = balance.today {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("今日")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                        moneyText(today, balance.currency, size: 10.5, weight: .semibold)
                    }
                }
            }
        } else {
            HStack {
                Text("DeepSeek 余额")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("打开 API Meter 配置 Key")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

struct CodingPlansView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemLarge {
                largeLayout
            } else {
                mediumLayout
            }
        }
        .containerBackground(for: .widget) { widgetGradient }
    }

    private var mediumLayout: some View {
        let providers = entry.snapshot.providers.filter(\.available)
        let rows = [Array(providers.prefix(2)), Array(providers.dropFirst(2).prefix(2))]
        return VStack(alignment: .leading, spacing: 8) {
            if providers.isEmpty {
                Text("未检测到 Coding Plan 凭据\n请打开 API Meter 配置")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                ForEach(0..<rows.count, id: \.self) { index in
                    HStack(spacing: 12) {
                        ForEach(rows[index]) { provider in
                            ProviderCell(
                                provider: provider,
                                windows: entry.snapshot.windows(for: provider),
                                now: entry.date
                            )
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(2)
    }
}

struct BalanceWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DeepSeek 余额")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            if let balance = entry.snapshot.balance {
                moneyText(balance.total, balance.currency, size: 23, weight: .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if let today = balance.today {
                    HStack(spacing: 4) {
                        Text("今日")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                        moneyText(today, balance.currency, size: 10, weight: .semibold)
                    }
                }
                if let fetchedAt = balance.fetchedAt {
                    Text("更新 " + fetchedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.45))
                }
            } else {
                Text("—")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text("打开 API Meter 配置 Key")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { widgetGradient }
    }
}
