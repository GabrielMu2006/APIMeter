import Foundation
import Observation

/// Kimi Code quota state. Nothing to configure: the credential is
/// auto-detected from the Kimi CLI's own storage, and when the ~15-minute
/// access token expires the store silently refreshes it with the stored
/// refresh token (the same call the CLI makes; the rotated tokens are
/// written back so the CLI keeps working). Only a dead refresh token is
/// terminal - surfaced as `credentialState == .expired` until the user
/// runs `kimi login` again.
///
/// On refresh failure the last successful quota is kept (spec 81).
@MainActor
@Observable
public final class KimiQuotaViewModel {
    /// Automatic refresh spacing, same as the ZCode quota provider.
    public static let minInterval: TimeInterval = 5 * 60
    /// Minimum spacing between token refresh attempts, so a dead refresh
    /// token cannot hammer the auth server from the 5-minute poller.
    public static let refreshRetryInterval: TimeInterval = 60

    public private(set) var quota: CodingPlanQuota?
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    public private(set) var credentialState: KimiCredentialState = .missing
    public private(set) var lastSuccessAt: Date?

    private let environment: AppEnvironment
    private var lastRefreshAttemptAt: Date?

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.credentialState = environment.kimiCredentialStore.load()
        self.quota = try? environment.repository.latestQuotaSnapshot(provider: UsageRepository.QuotaProviderKey.kimi)
    }

    /// True when the Kimi CLI credential is usable right now.
    public var hasCredential: Bool {
        if case .available = credentialState { return true }
        return false
    }

    public func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastSuccessAt, Date().timeIntervalSince(lastSuccessAt) < Self.minInterval {
            return
        }
        isLoading = true
        defer { isLoading = false }
        // Re-detect on every refresh: the CLI may have logged in/out since.
        credentialState = environment.kimiCredentialStore.load()

        switch credentialState {
        case .missing:
            lastError = nil // steady state, not an error banner
            return
        case .available:
            break
        case .expired:
            // Self-refresh with the stored refresh token (throttled).
            if let last = lastRefreshAttemptAt,
               Date().timeIntervalSince(last) < Self.refreshRetryInterval {
                return // keep last good data; do not hammer the auth server
            }
            lastRefreshAttemptAt = Date()
            do {
                credentialState = try await environment.kimiCredentialStore.refresh()
            } catch {
                lastError = error.localizedDescription
                return
            }
            guard case .available(let credential) = credentialState else {
                lastError = KimiError.authenticationFailed.localizedDescription
                return
            }
            _ = credential
        }

        do {
            guard case .available(let credential) = credentialState else { return }
            let quota = try await environment.kimiQuotaProvider(credential).fetchQuota()
            self.quota = quota
            self.lastError = nil
            self.lastSuccessAt = Date()
            try? environment.repository.saveQuotaSnapshot(quota, provider: UsageRepository.QuotaProviderKey.kimi)
            var weeklyText = "n/a"
            if let percent = quota.weekly?.usedPercent {
                weeklyText = String(describing: percent) + "%"
            }
            Log.info("Kimi quota refreshed (weekly " + weeklyText + ")")
        } catch {
            lastError = error.localizedDescription
        }
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
