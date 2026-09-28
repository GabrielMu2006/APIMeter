import XCTest
@testable import APIMeter

/// The widget snapshot is the contract between the main app and the
/// WidgetKit extension: written as JSON, read by the extension's own
/// field-compatible mirror. This tests the app side: encode -> file ->
/// decode roundtrip, ISO8601 dates, and the provider/window mapping from
/// the view models' domain types.
@MainActor
final class WidgetStateStoreTests: XCTestCase {

    func testWriteAndReadRoundtrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WidgetStateStore(fileURL: url)

        let fetchedAt = Date(timeIntervalSince1970: 1_789_900_000) // whole seconds: ISO8601-safe
        let snapshot = WidgetSnapshot(
            writtenAt: fetchedAt,
            balance: WidgetSnapshot.BalanceInfo(
                total: Decimal(string: "128.40")!,
                currency: "CNY",
                today: Decimal(string: "3.26")!,
                isAvailable: true,
                fetchedAt: fetchedAt
            ),
            providers: [
                WidgetSnapshot.ProviderInfo(
                    id: "codex",
                    displayName: "Codex",
                    available: true,
                    offline: true,
                    planLevel: "plus",
                    fetchedAt: fetchedAt,
                    windows: [
                        WidgetSnapshot.WindowInfo(kind: "fiveHour", remainingPercent: 42.5, resetsAt: fetchedAt),
                        WidgetSnapshot.WindowInfo(kind: "weekly", remainingPercent: 61, resetsAt: nil),
                    ]
                ),
                WidgetSnapshot.ProviderInfo(id: "kimi", displayName: "Kimi", available: false, offline: false, planLevel: nil, fetchedAt: nil, windows: []),
            ]
        )

        store.write(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(snapshot, decoded)
        XCTAssertEqual(decoded.providers.first?.windows.first?.kind, "fiveHour")
        XCTAssertEqual(decoded.balance?.currency, "CNY")
    }

    func testWidgetSnapshotMappingFromQuota() {
        let quota = CodingPlanQuota(
            planLevel: "pro",
            windows: [
                QuotaWindow(kind: .fiveHour, usedPercent: Decimal(string: "55.5")!, usedValue: nil, totalValue: nil, remaining: nil, resetsAt: nil),
                QuotaWindow(kind: .weekly, usedPercent: 20, usedValue: nil, totalValue: nil, remaining: nil, resetsAt: nil),
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_789_900_000)
        )
        let state = try! AppState(environment: .ephemeral())

        let provider = state.widgetProvider("zcode", "ZCode", quota, offline: false)
        XCTAssertTrue(provider.available)
        XCTAssertEqual(provider.windows.count, 2)
        XCTAssertEqual(provider.windows[0].kind, "fiveHour")
        XCTAssertEqual(provider.windows[0].remainingPercent ?? 0, 44.5, accuracy: 0.01)

        let missing = state.widgetProvider("kimi", "Kimi", nil, offline: false)
        XCTAssertFalse(missing.available)
        XCTAssertTrue(missing.windows.isEmpty)
    }
}
