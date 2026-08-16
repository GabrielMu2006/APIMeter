import Charts
import SwiftUI

/// 7-day mini bar trend for the quick panel (spec 33).
struct MiniTrendChart: View {
    let daily: [DailyUsage]

    private struct Entry: Identifiable {
        let id: LocalDay
        let cost: Double
        let official: Bool
    }

    private var entries: [Entry] {
        daily.map { day in
            Entry(id: day.day, cost: Double(truncating: (day.cost ?? 0) as NSDecimalNumber), official: day.verification == .official)
        }
    }

    var body: some View {
        if entries.isEmpty {
            Text("No history yet").font(.caption).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 32)
        } else {
            Chart(entries) { entry in
                BarMark(
                    x: .value("Day", entry.id.value),
                    y: .value("Cost", entry.cost)
                )
                .foregroundStyle(entry.official ? Color.accentColor : Color.secondary.opacity(0.45))
                .cornerRadius(1)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 36)
        }
    }
}
