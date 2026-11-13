import Foundation
import Observation

/// Cursor (Cursor Pro plan) quota state. The credential is auto-detected
/// from the Cursor GUI's local state database; the WorkOS token lives
/// about two months and Cursor rotates it on its own - no refresh flow
/// here. On refresh failure the last successful quota is kept (spec 81).
@MainActor
@Observable
public final class CursorQuotaViewModel {
    /// Automatic refresh spacing, same as the other quota providers.
    public static let minInterval: TimeInterval = 5 * 60

    public private(set) var quota: CodingPlanQuota?
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    public private(set) var credentialState: CursorCredentialState = .missing
    public private(set) var lastSuccessAt: Date?

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.credentialState = environment.cursorCredentialStore.load()
        self.quota = try? environment.repository.latestQuotaSnapshot(provider: UsageRepository.QuotaProviderKey.cursor)
    }

    /// True when the Cursor credential is usable right now.
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
        // Re-detect on every refresh: the user may have logged in/out.
        credentialState = environment.cursorCredentialStore.load()

        guard case .available(let credential) = credentialState else {
            lastError = nil // steady state, not an error banner
            return
        }

        do {
            let quota = try await environment.cursorQuotaProvider(credential).fetchQuota()
            self.quota = quota
            self.lastError = nil
            self.lastSuccessAt = Date()
            try? environment.repository.saveQuotaSnapshot(quota, provider: UsageRepository.QuotaProviderKey.cursor)
            WidgetStateStore.postDataChange()
            var cycleText = "n/a"
            if let percent = quota.monthly?.usedPercent {
                cycleText = String(describing: percent) + "%"
            }
            Log.info("Cursor quota refreshed (cycle used " + cycleText + ")")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Human countdown to the billing-cycle reset, e.g. "3d 4h". Nil when unknown.
    public func resetsIn(_ window: QuotaWindow?, now: Date = Date()) -> String? {
        guard let resetsAt = window?.resetsAt, resetsAt > now else { return nil }
        let remaining = Int(resetsAt.timeIntervalSince(now))
        let days = remaining / 86400
        let hours = (remaining % 86400) / 3600
        if days > 0 {
            return String(days) + "d " + String(hours) + "h"
        }
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
