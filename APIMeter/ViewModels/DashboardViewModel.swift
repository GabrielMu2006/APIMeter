import Foundation
import Observation

/// Drives the dashboard aggregates: period range, key filter, summaries.
@MainActor
@Observable
public final class DashboardViewModel {
    public enum RangePreset: String, CaseIterable, Identifiable, Sendable {
        case days7 = "7D"
        case days30 = "30D"
        case month = "Month"
        case custom = "Custom"
        public var id: String { rawValue }
    }

    public var preset: RangePreset = .days30
    public var customStart = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    public var customEnd = Date()
    public var selectedFingerprints: Set<String> = []
    public private(set) var summary: UsageSummary?
    public private(set) var today: DailyUsage?
    public private(set) var gatewayToday: DailyUsage?
    public private(set) var apiKeys: [APIKey] = []
    public private(set) var isLoading = false
    public private(set) var lastReload: Date?

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var range: (LocalDay, LocalDay) {
        let now = LocalDay(date: Date())
        switch preset {
        case .days7: return (now.adding(days: -6), now)
        case .days30: return (now.adding(days: -29), now)
        case .month:
            let comps = Calendar.current.dateComponents([.year, .month], from: Date())
            if let first = Calendar.current.date(from: comps) {
                return (LocalDay(date: first), now)
            }
            return (now.adding(days: -29), now)
        case .custom:
            let start = LocalDay(date: customStart)
            let end = LocalDay(date: customEnd)
            return start <= end ? (start, end) : (end, start)
        }
    }

    public func reload() async {
        isLoading = true
        defer { isLoading = false }
        apiKeys = (try? environment.repository.fetchAPIKeys()) ?? []
        let (start, end) = range
        let filter = selectedFingerprints.isEmpty ? nil : selectedFingerprints
        summary = try? environment.repository.summary(from: start, to: end, fingerprints: filter)
        if let summary {
            Log.info("Dashboard loaded: range=" + start.value + ".." + end.value + " days=" + String(summary.daily.count) + " cost=" + (summary.cost.map(DecimalStorage.string) ?? "nil") + " keys=" + String(summary.byAPIKey.count))
        } else {
            Log.info("Dashboard loaded: no data in range " + start.value + ".." + end.value)
        }
        // Today is always shown separately (spec 43). The gateway-only view
        // powers the live hint when official data already covers the day.
        let now = LocalDay(date: Date())
        today = (try? environment.repository.summary(from: now, to: now, fingerprints: nil))?.daily.first
        let todayRecords = (try? environment.repository.recordsInRange(from: now, to: now, fingerprints: nil)) ?? []
        let gatewayOnly = todayRecords.filter { $0.source == .localGateway }
        gatewayToday = UsageAggregator.daily(from: gatewayOnly).first
        lastReload = Date()
    }

    public func dayDetail(_ day: LocalDay) async -> UsageSummary? {
        let filter = selectedFingerprints.isEmpty ? nil : selectedFingerprints
        return try? environment.repository.summary(from: day, to: day, fingerprints: filter)
    }

    public func selectAllKeys() {
        selectedFingerprints = Set(apiKeys.map(\.fingerprint))
    }

    public func clearKeySelection() {
        selectedFingerprints = []
    }
}
