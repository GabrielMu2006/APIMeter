import Charts
import SwiftUI

/// Daily cost trend (spec 40). Official days are solid, estimated days are
/// translucent. Amounts come from the aggregation layer - never computed here.
struct UsageChart: View {
    let daily: [DailyUsage]

    private struct Entry: Identifiable {
        let id: LocalDay
        let date: Date
        let cost: Double
        let official: Bool
    }

    private var entries: [Entry] {
        let timeZone = TimeZone.autoupdatingCurrent
        return daily.map { day in
            Entry(
                id: day.day,
                date: day.day.start(in: timeZone),
                cost: Double(truncating: (day.cost ?? 0) as NSDecimalNumber),
                official: day.verification == .official
            )
        }
    }

    var body: some View {
        if entries.isEmpty {
            EmptyStateView()
                .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            Chart(entries) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Cost", entry.cost)
                )
                .foregroundStyle(entry.official ? Color.accentColor : Color.secondary.opacity(0.45))
                .cornerRadius(2)
            }
            .chartYAxisLabel("Cost")
            .frame(minHeight: 220)
        }
    }
}
