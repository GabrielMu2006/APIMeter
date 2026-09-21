import Foundation
import Observation

/// Qoder (CN desktop app) quota state. Nothing to configure: the credential
/// is auto-detected from the Qoder desktop app's encrypted auth file. The
/// token lives about a month and does not rotate on use, so there is no
/// refresh machinery - only a desktop-app re-login changes anything.
///
/// Exposes two credit pools: the personal monthly quota and (when the org
/// has one provisioned) the team org resource package. On refresh failure
/// the last successful quota is kept (spec 81).
@MainActor
@Observable
public final class QoderQuotaViewModel {
    /// Automatic refresh spacing, same as the other quota providers.
    public static let minInterval: TimeInterval = 5 * 60

    public private(set) var quota: CodingPlanQuota?
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    public private(set) var credentialState: QoderCredentialState = .missing
    public private(set) var lastSuccessAt: Date?

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.credentialState = environment.qoderCredentialStore.load()
        self.quota = try? environment.repository.latestQuotaSnapshot(provider: UsageRepository.QuotaProviderKey.qoder)
    }

    /// True when the Qoder credential is usable right now.
    public var hasCredential: Bool {
        if case .available = credentialState { return true }
        return false
    }

    /// The org pool only appears when the org actually has a package.
    public var hasOrgPool: Bool { quota?.orgMonthly != nil }

    public func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastSuccessAt, Date().timeIntervalSince(lastSuccessAt) < Self.minInterval {
            return
        }
        isLoading = true
        defer { isLoading = false }
        // Re-detect on every refresh: the desktop app may have logged in/out.
        credentialState = environment.qoderCredentialStore.load()
        guard case .available(let credential) = credentialState else {
            if case .expired = credentialState {
                lastError = QoderError.authenticationFailed.localizedDescription
            } else {
                lastError = nil
            }
            return
        }
        do {
            let quota = try await environment.qoderQuotaProvider(credential).fetchQuota()
            self.quota = quota
            self.lastError = nil
            self.lastSuccessAt = Date()
            try? environment.repository.saveQuotaSnapshot(quota, provider: UsageRepository.QuotaProviderKey.qoder)
            var personalText = "n/a"
            if let percent = quota.monthly?.usedPercent {
                personalText = String(describing: percent) + "%"
            }
            Log.info("Qoder quota refreshed (personal used " + personalText + ")")
        } catch {
            lastError = error.localizedDescription
        }
    }
}
