import XCTest
@testable import APIMeter

/// ZCodeQuotaViewModel behavior: fetch throttling, last-good retention,
/// no-key steady state. Uses a stub quota provider and an isolated Keychain
/// service so tests never touch the user's real Coding Plan key.
@MainActor
final class ZCodeQuotaViewModelTests: XCTestCase {

    private final class StubQuotaProvider: CodingPlanQuotaProvider, @unchecked Sendable {
        var calls = 0
        var result: Result<CodingPlanQuota, Error>

        init(result: Result<CodingPlanQuota, Error>) {
            self.result = result
        }

        func fetchQuota() async throws -> CodingPlanQuota {
            calls += 1
            switch result {
            case .success(let quota): return quota
            case .failure(let error): throw error
            }
        }
    }

    private static func fixedQuota() -> CodingPlanQuota {
        CodingPlanQuota(
            planLevel: "pro",
            windows: [
                QuotaWindow(kind: .fiveHour, usedPercent: 30, usedValue: 300, totalValue: 1000, remaining: 700, resetsAt: Date().addingTimeInterval(3600), modelDetails: []),
                QuotaWindow(kind: .weekly, usedPercent: 61, usedValue: 610, totalValue: 1000, remaining: 390, resetsAt: Date().addingTimeInterval(3600 * 24), modelDetails: []),
            ],
            fetchedAt: Date()
        )
    }

    /// Ephemeral environment whose ZCode key pool is a throwaway Keychain
    /// service, with a synthetic key saved and the stub provider injected.
    private func makeEnvironment(provider: StubQuotaProvider) throws -> (AppEnvironment, KeychainService, String) {
        let keychain = KeychainService(service: "com.apimeter.tests.zcode-" + UUID().uuidString)
        let fingerprint = try keychain.saveAPIKey("sk-test-zcode-" + UUID().uuidString)
        let environment = try AppEnvironment.ephemeral(zcodeKeychain: keychain, quotaProvider: { _, _ in provider })
        return (environment, keychain, fingerprint)
    }

    func testRefreshThrottlesToMinInterval() async throws {
        let provider = StubQuotaProvider(result: .success(Self.fixedQuota()))
        let (environment, keychain, fingerprint) = try makeEnvironment(provider: provider)
        defer { try? keychain.deleteAPIKey(fingerprint: fingerprint) }

        let viewModel = ZCodeQuotaViewModel(environment: environment)
        await viewModel.refresh(force: true)
        XCTAssertNotNil(viewModel.quota, "first refresh populates quota")
        await viewModel.refresh()
        XCTAssertEqual(provider.calls, 1, "second refresh within minInterval must not fetch")

        await viewModel.refresh(force: true)
        XCTAssertEqual(provider.calls, 2, "force bypasses the throttle")
    }

    func testKeepsLastGoodQuotaOnError() async throws {
        let provider = StubQuotaProvider(result: .success(Self.fixedQuota()))
        let (environment, keychain, fingerprint) = try makeEnvironment(provider: provider)
        defer { try? keychain.deleteAPIKey(fingerprint: fingerprint) }

        let viewModel = ZCodeQuotaViewModel(environment: environment)
        await viewModel.refresh(force: true)
        let goodQuota = viewModel.quota
        XCTAssertNotNil(goodQuota)

        provider.result = .failure(ZCodeError.rateLimited)
        await viewModel.refresh(force: true)
        XCTAssertEqual(viewModel.quota, goodQuota, "failed refresh must keep the last good quota")
        XCTAssertNotNil(viewModel.lastError)
    }

    func testNoKeyIsSteadyStateWithoutFetch() async throws {
        let provider = StubQuotaProvider(result: .success(Self.fixedQuota()))
        let keychain = KeychainService(service: "com.apimeter.tests.zcode-" + UUID().uuidString)
        let environment = try AppEnvironment.ephemeral(zcodeKeychain: keychain, quotaProvider: { _, _ in provider })

        let viewModel = ZCodeQuotaViewModel(environment: environment)
        XCTAssertFalse(viewModel.hasStoredKey)
        await viewModel.refresh(force: true)
        XCTAssertEqual(provider.calls, 0, "no key configured must not hit the network")
        XCTAssertNil(viewModel.lastError, "missing key is a steady state, not an error")
    }
}
