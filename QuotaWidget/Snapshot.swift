import Foundation
import os

private let logger = Logger(subsystem: "com.apimeter", category: "quota-widget")

/// Field-compatible mirror of the main app's WidgetSnapshot (APIMeter/
/// App/WidgetStateStore.swift). The extension shares no code with the app,
/// so this file is the contract - keep field names in sync.
struct WidgetSnapshot: Codable, Equatable {
    var version: Int
    var writtenAt: Date
    var balance: BalanceInfo?
    var providers: [ProviderInfo]

    struct BalanceInfo: Codable, Equatable {
        var total: Decimal
        var currency: String
        var today: Decimal?
        var isAvailable: Bool
        var fetchedAt: Date?
    }

    struct ProviderInfo: Codable, Equatable, Identifiable {
        var id: String
        var displayName: String
        var available: Bool
        var offline: Bool
        var planLevel: String?
        var fetchedAt: Date?
        var windows: [WindowInfo]
    }

    struct WindowInfo: Codable, Equatable {
        var kind: String
        var remainingPercent: Double?
        var remainingLabel: String?
        var resetsAt: Date?
    }

    /// The two windows a provider shows (5-hour + weekly, or the Qoder
    /// monthly pair).
    func windows(for provider: ProviderInfo) -> [WindowInfo] {
        if provider.windows.contains(where: { $0.kind == "fiveHour" }) {
            return ["fiveHour", "weekly"].compactMap { window(kind: $0, in: provider) }
        }
        return ["monthly", "orgMonthly"].compactMap { window(kind: $0, in: provider) }
    }

    private func window(kind: String, in provider: ProviderInfo) -> WindowInfo? {
        provider.windows.first { $0.kind == kind }
    }
}

/// Reads the snapshot the main app writes after every refresh. The widget
/// process is sandboxed, so the primary location is its own container's
/// Data directory (NSHomeDirectory) - the unsandboxed main app writes there.
/// The app-support path behind the temporary-exception entitlement stays as
/// a fallback. With neither file readable (first launch, gallery preview) a
/// fixed sample keeps the layout honest.
enum WidgetSnapshotLoader {
    static var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("widget-state.json")
    }

    static var legacyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("APIMeter/widget-state.json")
    }

    static func load() -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in [fileURL, legacyFileURL] {
            if let data = try? Data(contentsOf: url),
               let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) {
                logger.info("snapshot loaded: \(url.path, privacy: .public)")
                return snapshot
            }
        }
        logger.notice("snapshot unavailable - rendering sample data")
        return nil
    }

    static func sample() -> WidgetSnapshot {
        let now = Date()
        func inMinutes(_ minutes: Int) -> Date {
            now.addingTimeInterval(TimeInterval(minutes) * 60)
        }
        return WidgetSnapshot(
            version: 1,
            writtenAt: now,
            balance: WidgetSnapshot.BalanceInfo(
                total: 128.40,
                currency: "CNY",
                today: 3.26,
                isAvailable: true,
                fetchedAt: now
            ),
            providers: [
                provider("zcode", "ZCode", fiveHour: 72, weekly: 55, resetMinutes: 143),
                provider("kimi", "Kimi", fiveHour: 88, weekly: 93, resetMinutes: 95),
                WidgetSnapshot.ProviderInfo(
                    id: "qoder", displayName: "Qoder", available: true, offline: false,
                    planLevel: nil, fetchedAt: now,
                    windows: [
                        WidgetSnapshot.WindowInfo(kind: "monthly", remainingPercent: 76, resetsAt: nil),
                    ]
                ),
                WidgetSnapshot.ProviderInfo(
                    id: "codex", displayName: "Codex", available: true, offline: true,
                    planLevel: "plus", fetchedAt: now,
                    windows: [
                        WidgetSnapshot.WindowInfo(kind: "fiveHour", remainingPercent: 95, resetsAt: inMinutes(42)),
                        WidgetSnapshot.WindowInfo(kind: "weekly", remainingPercent: 60, resetsAt: nil),
                    ]
                ),
            ]
        )
    }

    private static func provider(_ id: String, _ name: String, fiveHour: Double, weekly: Double, resetMinutes: Int) -> WidgetSnapshot.ProviderInfo {
        WidgetSnapshot.ProviderInfo(
            id: id,
            displayName: name,
            available: true,
            offline: false,
            planLevel: nil,
            fetchedAt: Date(),
            windows: [
                WidgetSnapshot.WindowInfo(kind: "fiveHour", remainingPercent: fiveHour, resetsAt: Date().addingTimeInterval(TimeInterval(resetMinutes) * 60)),
                WidgetSnapshot.WindowInfo(kind: "weekly", remainingPercent: weekly, resetsAt: nil),
            ]
        )
    }
}
