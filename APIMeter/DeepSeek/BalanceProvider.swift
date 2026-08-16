import Foundation

/// Provider abstraction (spec §69) so business logic never binds to one vendor.
public protocol BalanceProvider: Sendable {
    func fetchBalance() async throws -> Balance
}

/// Fetches the balance using the API key stored in Keychain for the given fingerprint.
public struct DeepSeekBalanceProvider: BalanceProvider {
    private let keychain: KeychainService
    private let fingerprint: String
    private let clientFactory: @Sendable (String) -> DeepSeekClient

    public init(keychain: KeychainService = KeychainService(), fingerprint: String, clientFactory: @escaping @Sendable (String) -> DeepSeekClient = { DeepSeekClient(apiKey: $0) }) {
        self.keychain = keychain
        self.fingerprint = fingerprint
        self.clientFactory = clientFactory
    }

    public func fetchBalance() async throws -> Balance {
        let key = try keychain.readAPIKey(fingerprint: fingerprint)
        let client = clientFactory(key)
        return try await client.fetchBalance()
    }
}
