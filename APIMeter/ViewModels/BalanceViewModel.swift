import Foundation
import Observation

/// Current balance state. On refresh failure the last successful balance is
/// kept (spec 81) - never replaced with zero or garbage.
@MainActor
@Observable
public final class BalanceViewModel {
    public private(set) var balance: Balance?
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    public private(set) var hasStoredKey = false
    public private(set) var activeFingerprint: String?

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
        let fingerprints = (try? environment.keychain.listFingerprints()) ?? []
        self.hasStoredKey = !fingerprints.isEmpty
        self.activeFingerprint = fingerprints.first
        self.balance = try? environment.repository.latestBalanceSnapshot()
    }

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let fingerprints = (try? environment.keychain.listFingerprints()) ?? []
        hasStoredKey = !fingerprints.isEmpty
        guard let fingerprint = fingerprints.first else {
            lastError = "No API key saved yet. Add one in Settings > DeepSeek."
            return
        }
        activeFingerprint = fingerprint
        do {
            let fresh = try await environment.balanceProvider(fingerprint).fetchBalance()
            balance = fresh
            lastError = nil
            try environment.repository.saveBalanceSnapshot(fresh)
            await environment.alertService.check(balance: fresh, threshold: environment.settings.balanceAlertThreshold)
            Log.info("Balance refreshed from API (fingerprint " + KeyFingerprint.displayPrefix(fingerprint, length: 8) + "...)")
        } catch {
            lastError = error.localizedDescription
        }
    }
}
