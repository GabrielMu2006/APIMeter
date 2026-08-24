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
    /// nil = all keys (default); empty set = none (Clear).
    public var selectedFingerprints: Set<String>?
    public private(set) var summary: UsageSummary?
    public private(set) var today: DailyUsage?
    public private(set) var todayBalanceEstimate: TodayBalanceEstimate?
    public private(set) var todayPartialEstimate: PartialTodayEstimate?
    /// Daily list INCLUDING a synthesized Today row (balance estimate) so
    /// the current day is visible before the official export covers it.
    public private(set) var dailyList: [DailyUsage] = []
    public private(set) var perKeyCostsByDay: [LocalDay: [(fingerprint: String, cost: Decimal)]] = [:]
    public private(set) var latestImportAt: Date?
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

    /// The cost shown on the Today card everywhere (menu bar, dashboard, mini):
    /// full balance-delta -> partial (since first snapshot) -> official fallback.
    public var todayDisplayCost: Decimal? {
        if let estimate = todayBalanceEstimate { return estimate.amount }
        if let partial = todayPartialEstimate { return partial.amount }
        return today?.cost
    }

    /// Human-readable source label for the Today card.
    public var todayDisplaySubtitle: String {
        if let estimate = todayBalanceEstimate {
            return estimate.topupDetected
                ? "Balance-derived · top-up masked some spending"
                : "Balance-derived"
        }
        if let partial = todayPartialEstimate {
            let base = "Balance-derived since " + partial.since.formatted(date: .omitted, time: .shortened) + " (no midnight baseline yet)"
            return partial.topupDetected ? base + " · top-up masked some spending" : base
        }
        if today != nil {
            return "Official export"
        }
        return "no data yet"
    }

    public func reload() async {
        isLoading = true
        defer { isLoading = false }
        apiKeys = (try? environment.repository.fetchAPIKeys()) ?? []
        let (start, end) = range
        let filter = selectedFingerprints
        let rangeRecords = (try? environment.repository.recordsInRange(from: start, to: end, fingerprints: filter)) ?? []
        perKeyCostsByDay = UsageAggregator.perKeyDailyCosts(rangeRecords)
        latestImportAt = (try? environment.repository.fetchImportBatches())?.first?.importedAt
        summary = try? environment.repository.summary(from: start, to: end, fingerprints: filter)
        if let summary {
            Log.info("Dashboard loaded: range=" + start.value + ".." + end.value + " days=" + String(summary.daily.count) + " cost=" + (summary.cost.map(DecimalStorage.string) ?? "nil") + " keys=" + String(summary.byAPIKey.count))
        } else {
            Log.info("Dashboard loaded: no data in range " + start.value + ".." + end.value)
        }
        // Today is always shown separately (spec 43): official CSV first,
        // then the balance-derived estimate as a fallback.
        let now = LocalDay(date: Date())
        today = (try? environment.repository.summary(from: now, to: now, fingerprints: nil))?.daily.first
        todayBalanceEstimate = try? environment.repository.estimatedTodaySpend()
        todayPartialEstimate = try? environment.repository.estimatedTodaySpendSinceFirstSnapshot()
        let officialDaily = summary?.daily ?? []
        let todayDay = LocalDay(date: Date())
        dailyList = Self.buildDailyList(
            official: officialDaily,
            todayRow: Self.synthesizeTodayRow(
                displayCost: todayDisplayCost,
                officialToday: officialDaily.first { $0.day == todayDay },
                day: todayDay
            )
        )
        lastReload = Date()
    }

    /// Builds the displayed daily list: official rows plus a synthesized
    /// Today row carrying the balance-derived estimate (verification =
    /// estimated unless official data covers today).
    private static func buildDailyList(official: [DailyUsage], todayRow: DailyUsage?) -> [DailyUsage] {
        var rows = official.filter { $0.day != todayRow?.day }
        if let todayRow { rows.append(todayRow) }
        return rows.sorted { $0.day > $1.day }
    }

    private static func synthesizeTodayRow(displayCost: Decimal?, officialToday: DailyUsage?, day: LocalDay) -> DailyUsage? {
        guard let cost = displayCost else { return officialToday }
        let requests = officialToday?.requests
        let tokens = officialToday?.tokens
        let verification: VerificationState = officialToday?.verification ?? .estimated
        let sources = officialToday?.sources ?? [.balanceSnapshot]
        return DailyUsage(day: day, cost: cost, requests: requests, tokens: tokens, verification: verification, sources: sources)
    }

    public func dayDetail(_ day: LocalDay) async -> UsageSummary? {
        return try? environment.repository.summary(from: day, to: day, fingerprints: selectedFingerprints)
    }

    public func selectAllKeys() {
        selectedFingerprints = Set(apiKeys.map(\.fingerprint))
    }

    /// Empty set = "No keys" (Clear shows nothing), nil = All.
    public func clearKeySelection() {
        selectedFingerprints = []
    }

    /// Toggles one key. nil (all) is treated as "all selected" first.
    public func toggleKey(_ fingerprint: String) {
        var set = selectedFingerprints ?? Set(apiKeys.map(\.fingerprint))
        if set.contains(fingerprint) {
            set.remove(fingerprint)
        } else {
            set.insert(fingerprint)
        }
        selectedFingerprints = set
    }

    /// Menu label: All Keys / No Keys / N of M Keys.
    public var filterLabelText: String {
        guard let selected = selectedFingerprints else { return "All Keys" }
        if selected.isEmpty { return "No Keys" }
        let total = apiKeys.count
        if total > 0 && selected.count >= total { return "All Keys" }
        return String(selected.count) + " of " + String(total) + " Keys"
    }
}
