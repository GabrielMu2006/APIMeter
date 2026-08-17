import Foundation
import Observation

/// App-side gateway lifecycle (spec 24/83). The gateway is a stable OPTIONAL
/// feature: when it cannot start, balance / CSV / dashboard are unaffected.
@MainActor
@Observable
public final class GatewayManager {
    public enum Status: String, Sendable {
        case stopped
        case running
        case failed
    }

    public private(set) var status: Status = .stopped
    public private(set) var errorMessage: String?
    public private(set) var endpoint: String?

    private var server: GatewayServer?
    private let settings: AppSettings
    private let repository: UsageRepository

    public init(settings: AppSettings, repository: UsageRepository) {
        self.settings = settings
        self.repository = repository
    }

    public var isRunning: Bool { status == .running }

    public func start() async {
        guard server == nil else { return }
        let collector = UsageCollector(repository: repository)
        let config = GatewayConfig(port: settings.gatewayPort, upstreamBaseURL: DeepSeekClient.baseURL)
        let newServer = GatewayServer(config: config, collector: collector)
        do {
            try await newServer.start()
            server = newServer
            endpoint = newServer.endpoint
            errorMessage = nil
            status = .running
            Log.info("Gateway started on " + (endpoint ?? "?"))
        } catch let error as GatewayError {
            server = nil
            errorMessage = error.errorDescription
            status = .failed
            Log.error("Gateway start failed: " + (error.errorDescription ?? "gateway error"))
        } catch {
            server = nil
            errorMessage = error.localizedDescription
            status = .failed
        }
    }

    public func stop() async {
        if let server {
            try? await server.stop()
        }
        server = nil
        endpoint = nil
        status = .stopped
        Log.info("Gateway stopped")
    }
}
