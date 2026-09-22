import Foundation
import Observation

/// Codex (ChatGPT plan) quota state. Nothing to configure: the credential is
/// auto-detected from the Codex CLI's auth.json. The access token lives
/// ~10 days (JWT exp checked locally); when it expires the store silently
/// refreshes it at auth.openai.com and writes the rotated tokens back with
/// a lineage check, so the CLI keeps working. Only a dead refresh token is
/// terminal - run `codex login` again.
///
/// On refresh failure the last successful quota is kept (spec 81).
@MainActor
@Observable
public final class CodexQuotaViewModel {
    /// Automatic refresh spacing, same as the other quota providers.
    public static let minInterval: TimeInterval = 5 * 60
    /// Minimum spacing between token refresh attempts, so a dead refresh
    /// token cannot hammer the auth server from the 5-minute poller.
    public static let refreshRetryInterval: TimeInterval = 60

    public private(set) var quota: CodingPlanQuota?
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    public private(set) var credentialState: CodexCredentialState = .missing
    public private(set) var lastSuccessAt: Date?
    /// True when the shown data came from the CLI's session log (offline
    /// fallback) instead of the live usage endpoint.
    public private(set) var usingSessionFallback = false

    private let environment: AppEnvironment
    private var lastRefreshAttemptAt: Date?

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.credentialState = environment.codexCredentialStore.load()
        self.quota = try? environment.repository.latestQuotaSnapshot(provider: UsageRepository.QuotaProviderKey.codex)
    }

    /// True when the Codex credential is usable right now.
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
        credentialState = environment.codexCredentialStore.load()

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
                credentialState = try await environment.codexCredentialStore.refresh()
            } catch {
                lastError = error.localizedDescription
                return
            }
            guard case .available = credentialState else {
                lastError = CodexError.authenticationFailed.localizedDescription
                return
            }
        }

        do {
            guard case .available(let credential) = credentialState else { return }
            // Read the proxy setting on every refresh so toggling it in
            // Settings takes effect on the next attempt without a relaunch.
            let proxy = environment.settings.codexProxyEnabled
                ? CodexProxyConfig.parse(environment.settings.codexProxyAddress)
                : nil
            let quota = try await environment.codexQuotaProvider(credential, proxy).fetchQuota()
            self.quota = quota
            self.usingSessionFallback = false
            self.lastError = nil
            self.lastSuccessAt = Date()
            try? environment.repository.saveQuotaSnapshot(quota, provider: UsageRepository.QuotaProviderKey.codex)
            var fiveHourText = "n/a"
            if let percent = quota.fiveHour?.usedPercent {
                fiveHourText = String(describing: percent) + "%"
            }
            Log.info("Codex quota refreshed (5h used " + fiveHourText + ")")
        } catch {
            // Offline fallback: the CLI records the same rate limits in its
            // session log after every call, so recent Codex usage still
            // shows even when chatgpt.com is unreachable from here.
            if let fallback = environment.codexSessionUsageReader.latestQuota() {
                self.quota = fallback
                self.usingSessionFallback = true
                self.lastError = nil
                try? environment.repository.saveQuotaSnapshot(fallback, provider: UsageRepository.QuotaProviderKey.codex)
                Log.info("Codex quota from session log (offline fallback, fetched " + fallback.fetchedAt.formatted(date: .omitted, time: .shortened) + ")")
            } else {
                lastError = error.localizedDescription
            }
        }
    }

    /// Human countdown to a window reset, e.g. "4h 32m". Nil when unknown.
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
