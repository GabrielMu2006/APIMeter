import Charts
import SwiftUI

/// Daily cost trend styled after the DeepSeek web usage page (spec 40):
/// blue rounded bars, clean date axis, hover tooltip with the day's
/// cost / requests / tokens.
struct UsageChart: View {
    let daily: [DailyUsage]
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
                AxisMarks(values: .stride(by: .day, count: axisStride)) { _ in
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
                                    guard let date: Date = proxy.value(atX: value.location.x) else {
                                        hoveredDay = nil
                                        return
                                    }
                                    hoveredDay = nearestEntry(to: date)?.id
                                }
                                .onEnded { _ in hoveredDay = nil }
                        )
                    if let hoveredDay,
                       let entry = entries.first(where: { $0.id == hoveredDay }),
                       let positionX = proxy.position(forX: entry.date) {
                        tooltip(for: entry)
                            .frame(width: 170)
                            .offset(x: min(max(positionX - 85, 4), geometry.size.width - 178), y: 6)
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

    /// Stride based on the TIME SPAN (the axis is continuous across all days,
    /// not only days with data) - keeps labels sparse like the web page.
    private var axisStride: Int {
        guard let first = entries.first?.date, let last = entries.last?.date else { return 1 }
        let spanDays = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        if spanDays > 60 { return 14 }
        if spanDays > 21 { return 7 }
        if spanDays > 10 { return 3 }
        return 1
    }

    private func nearestEntry(to date: Date) -> Entry? {
        entries.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    @ViewBuilder
    private func tooltip(for entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.id.value)
                .font(.caption.weight(.semibold))
            Text("Cost  " + CurrencyFormatter.format(Decimal(entry.cost), currency: "CNY"))
                .font(.caption)
            Text("Requests  " + (entry.requests.map(String.init) ?? "—"))
                .font(.caption)
            Text("Tokens  " + (entry.tokens.map(TokenFormatter.compact) ?? "—"))
                .font(.caption)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 1))
        .shadow(radius: 6, y: 2)
        .allowsHitTesting(false)
    }
}
