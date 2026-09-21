import Foundation
import Observation

/// ZCode (Zhipu Coding Plan) quota state. Mirrors BalanceViewModel:
/// on refresh failure the last successful quota is kept (spec 81), never
/// replaced with zeros.
///
/// The quota monitor endpoint is more rate-limit-sensitive than the balance
/// API, so automatic refreshes are throttled to one per `minInterval`
/// (5 minutes). Manual actions (Test Connection, the Refresh button) pass
/// force: true to bypass the guard.
@MainActor
@Observable
public final class ZCodeQuotaViewModel {
    /// Automatic refresh spacing for the quota endpoint.
    public static let minInterval: TimeInterval = 5 * 60

    public private(set) var quota: CodingPlanQuota?
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    public private(set) var hasStoredKey = false
    public private(set) var activeFingerprint: String?
    public private(set) var lastSuccessAt: Date?

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
        let fingerprints = (try? environment.zcodeKeychain.listFingerprints()) ?? []
        self.hasStoredKey = !fingerprints.isEmpty
        self.quota = try? environment.repository.latestQuotaSnapshot(provider: environment.settings.zcodeRegion.rawValue)
    }

    public func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastSuccessAt, Date().timeIntervalSince(lastSuccessAt) < Self.minInterval {
            return
        }
        isLoading = true
        defer { isLoading = false }
        let fingerprints = (try? environment.zcodeKeychain.listFingerprints()) ?? []
        hasStoredKey = !fingerprints.isEmpty
        guard let fingerprint = fingerprints.first else {
            // No key configured is a steady state, not an error banner.
            return
        }
        activeFingerprint = fingerprint
        do {
            guard let key = try? environment.zcodeKeychain.readAPIKey(fingerprint: fingerprint) else {
                throw ZCodeError.authenticationFailed
            }
            let region = environment.settings.zcodeRegion
            let client = environment.quotaProvider(region, key)
            let quota = try await client.fetchQuota()
            self.quota = quota
            self.lastError = nil
            self.lastSuccessAt = Date()
            try? environment.repository.saveQuotaSnapshot(quota, provider: region.rawValue)
            var fiveHourText = "n/a"
            if let percent = quota.fiveHour?.usedPercent {
                fiveHourText = String(describing: percent) + "%"
            }
            var weeklyText = "n/a"
            if let percent = quota.weekly?.usedPercent {
                weeklyText = String(describing: percent) + "%"
            }
            Log.info("ZCode quota refreshed (5h " + fiveHourText + ", weekly " + weeklyText + ")")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Drops the in-memory throttle marker so the next refresh runs even
    /// within minInterval (used after settings change the key or region).
    public func resetThrottle() {
        lastSuccessAt = nil
    }

    /// Human countdown to a window reset, e.g. "2:14". Nil when unknown.
    public func resetsIn(_ window: QuotaWindow?, now: Date = Date()) -> String? {
        guard let resetsAt = window?.resetsAt, resetsAt > now else { return nil }
        let remaining = Int(resetsAt.timeIntervalSince(now))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return String(hours) + "h " + String(minutes) + "m"
        }
        if remaining >= 60 {
            return String(minutes) + "m"
        }
        return "<1m"
    }
}
