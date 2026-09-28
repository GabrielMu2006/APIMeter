import WidgetKit
import SwiftUI

@main
struct QuotaWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodingPlansWidget()
        BalanceWidget()
    }
}

/// Coding plans: medium = rings-only grid, large = balance header + one
/// card per provider (the full panel).
struct CodingPlansWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.apimeter.codingPlans", provider: SnapshotProvider()) { entry in
            CodingPlansView(entry: entry)
        }
        .configurationDisplayName("Coding Plan 额度")
        .description("ZCode / Kimi / Qoder / Codex 剩余额度与重置倒计时；大号含 DeepSeek 余额")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Small widget: DeepSeek balance and today's spend.
struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.apimeter.balance", provider: SnapshotProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("DeepSeek 余额")
        .description("当前余额与今日消费")
        .supportedFamilies([.systemSmall])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// The app reloads timelines after every refresh (WidgetCenter); the 15
/// minute fallback only covers the case where the app is not running.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSnapshotLoader.sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(entry(context: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let current = entry(context: context)
        completion(Timeline(entries: [current], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func entry(context: Context) -> SnapshotEntry {
        let snapshot = WidgetSnapshotLoader.load() ?? WidgetSnapshotLoader.sample()
        return SnapshotEntry(date: Date(), snapshot: snapshot)
    }
}
