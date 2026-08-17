import Charts
import SwiftUI

/// Daily cost trend styled after the DeepSeek web usage page (spec 40):
/// blue rounded bars, sparse date axis, hover tooltip with the day's
/// cost / requests / tokens and the per-key cost breakdown.
struct UsageChart: View {
    let daily: [DailyUsage]
    let perKeyCosts: [LocalDay: [(name: String, cost: Decimal)]]
    @State private var hoveredDay: LocalDay?

    private struct Entry: Identifiable {
        let id: LocalDay
        let date: Date
        let cost: Double
        let official: Bool
        let requests: Int64?
        let tokens: Int64?
    }

    private var entries: [Entry] {
        let timeZone = TimeZone.autoupdatingCurrent
        return daily.map { day in
            Entry(
                id: day.day,
                date: day.day.start(in: timeZone),
                cost: Double(truncating: (day.cost ?? 0) as NSDecimalNumber),
                official: day.verification == .official,
                requests: day.requests,
                tokens: day.tokens
            )
        }
    }

    var body: some View {
        if entries.isEmpty {
            EmptyStateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(entries) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Cost", entry.cost)
                )
                .foregroundStyle(entry.official ? officialGradient : estimateGradient)
                .cornerRadius(4)
            }
            .chartYAxisLabel("Cost")
            .chartXAxis {
                AxisMarks(values: axisMarkDates) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.25))
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(.defaultDigits))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.25))
                    AxisValueLabel().foregroundStyle(.secondary)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Band-based matching: each entry owns the
                                    // pixel interval [date, date+1day). The
                                    // cursor's band wins - independent of how
                                    // Swift Charts centers the drawn bar.
                                    let plotMinX = (proxy.plotFrame.flatMap { geometry[$0] })?.minX ?? 0
                                    let cursorX = value.location.x
                                    var matched: Entry?
                                    for entry in entries {
                                        guard let startX = proxy.position(forX: entry.date) else { continue }
                                        let bandStart = startX + plotMinX
                                        let bandEnd = (proxy.position(forX: entry.date.addingTimeInterval(86_400)) ?? startX) + plotMinX
                                        if cursorX >= bandStart && cursorX < bandEnd {
                                            matched = entry
                                            break
                                        }
                                    }
                                    hoveredDay = matched?.id
                                }
                                .onEnded { _ in hoveredDay = nil }
                        )
                    if let hoveredDay,
                       let entry = entries.first(where: { $0.id == hoveredDay }),
                       let startX = proxy.position(forX: entry.date) {
                        // Center the tooltip over the entry's day band.
                        let plotMinX = ((proxy.plotFrame.flatMap { geometry[$0] })?.minX ?? 0)
                        let bandStart = startX + plotMinX
                        let bandEnd = (proxy.position(forX: entry.date.addingTimeInterval(86_400)) ?? startX) + plotMinX
                        let centerX = (bandStart + bandEnd) / 2
                        tooltip(for: entry)
                            .frame(width: 180)
                            .offset(x: min(max(centerX - 90, 4), geometry.size.width - 188), y: 6)
                    }
                }
            }
        }
    }

    private var officialGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue.opacity(0.95), Color.blue.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var estimateGradient: LinearGradient {
        LinearGradient(
            colors: [Color.secondary.opacity(0.6), Color.secondary.opacity(0.3)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Labels sit exactly UNDER bars: stride over DATA POINTS (not empty
    /// calendar days), at most 5 labels. No label ever floats in empty space.
    private var axisMarkDates: [Date] {
        let count = entries.count
        guard count > 0 else { return [] }
        let stride = max(1, Int(ceil(Double(count) / 5.0)))
        var dates: [Date] = []
        for (index, entry) in entries.enumerated() {
            if index % stride == 0 || index == count - 1 {
                dates.append(entry.date)
            }
        }
        return dates
    }

    @ViewBuilder
    private func tooltip(for entry: Entry) -> some View {
        let keys = perKeyCosts[entry.id] ?? []
        let costText = CurrencyFormatter.format(Decimal(entry.cost), currency: "CNY")
        let requestsText = entry.requests.map(String.init) ?? "?"
        let tokensText = entry.tokens.map(TokenFormatter.compact) ?? "?"
        let visibleKeys = Array(keys.prefix(5))
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.id.value)
                .font(.caption.weight(.semibold))
            Text("Cost  " + costText)
                .font(.caption)
            Text("Requests  " + requestsText + "  Tokens  " + tokensText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !visibleKeys.isEmpty {
                Divider()
                ForEach(visibleKeys, id: \.name) { key in
                    HStack {
                        Text(key.name)
                            .lineLimit(1)
                        Spacer()
                        Text(CurrencyFormatter.format(key.cost, currency: "CNY"))
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
                if keys.count > 5 {
                    Text("+" + String(keys.count - 5) + " more keys")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 1))
        .shadow(radius: 6, y: 2)
        .allowsHitTesting(false)
    }
}
