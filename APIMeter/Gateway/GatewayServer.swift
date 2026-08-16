import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1

public struct GatewayConfig: Sendable {
    public var port: Int
    public var upstreamBaseURL: URL
    public var maxRequestBodyBytes: Int
    public var maxResponseBodyBytes: Int
    public var requestTimeout: TimeInterval

    public init(
        port: Int = 43123,
        upstreamBaseURL: URL = DeepSeekClient.baseURL,
        maxRequestBodyBytes: Int = 16 * 1024 * 1024,
        maxResponseBodyBytes: Int = 64 * 1024 * 1024,
        requestTimeout: TimeInterval = 600
    ) {
        self.port = port
        self.upstreamBaseURL = upstreamBaseURL
        self.maxRequestBodyBytes = maxRequestBodyBytes
        self.maxResponseBodyBytes = maxResponseBodyBytes
        self.requestTimeout = requestTimeout
    }
}

public enum GatewayError: Error, LocalizedError {
    case portInUse(Int)
    case bindFailed(String)
    case invalidRequest

    public var errorDescription: String? {
        switch self {
        case .portInUse(let port):
            return "Gateway unavailable. Port " + String(port) + " is already in use."
        case .bindFailed(let reason):
            return "Gateway could not start: " + reason
        case .invalidRequest:
            return "Gateway received a request it cannot forward."
        }
    }
}

/// Phase A gateway feasibility proof:
/// - listens ONLY on 127.0.0.1 (0.0.0.0 is forbidden by spec 20)
/// - transparently forwards requests to DeepSeek (never modifies body/params)
/// - supports non-streaming and streaming responses (streaming is relayed
///   chunk-by-chunk, never fully buffered, spec 23)
/// - collects usage metadata only (prompts/completions are never stored)
public final class GatewayServer: @unchecked Sendable {
    private let group: MultiThreadedEventLoopGroup
    private let config: GatewayConfig
    private let collector: UsageCollector
    private let lock = NSLock()
    private var _channel: Channel?

    public init(config: GatewayConfig, collector: UsageCollector) {
        self.config = config
        self.collector = collector
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    }

    deinit {
        try? group.syncShutdownGracefully()
    }

    public func start() async throws {
        guard withLock({ _channel }) == nil else { return }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(GatewayHTTPHandler(config: self.config, collector: self.collector))
                }
            }
        do {
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: config.port).get()
            withLock { _channel = channel }
            Log.info("Gateway listening on http://127.0.0.1:" + String(config.port))
        } catch let error as IOError where error.errnoCode == EADDRINUSE {
            throw GatewayError.portInUse(config.port)
        } catch {
            throw GatewayError.bindFailed(String(describing: error))
        }
    }

    public var isRunning: Bool {
        withLock { _channel != nil }
    }

    public var endpoint: String? {
        isRunning ? "http://127.0.0.1:" + String(config.port) : nil
    }

    public func stop() async throws {
        let channel = withLock { _channel }
        if let channel {
            try await channel.close(mode: .all).get()
            withLock { _channel = nil }
        }
    }

    /// Synchronous lock scope (NSLock is not usable directly from async contexts).
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Handles one HTTP request: accumulates the body, then relays it upstream.
/// All state lives on the channel's event loop.
final class GatewayHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private enum State {
        case idle
        case body(HTTPRequestHead, ByteBuffer)
        case relaying
        case done
    }

    private let config: GatewayConfig
    private let collector: UsageCollector
    private var state: State = .idle
    private var relayContext: ChannelHandlerContext?

    init(config: GatewayConfig, collector: UsageCollector) {
        self.config = config
        self.collector = collector
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        switch (state, part) {
        case (.idle, .head(let head)):
            guard let value = head.headers["content-length"].first,
                  let length = Int(value),
                  length <= config.maxRequestBodyBytes else {
                reject(context: context, status: .badRequest, message: "missing content-length or body too large")
                state = .done
                return
            }
            let buffer = context.channel.allocator.buffer(capacity: max(length, 1))
            state = .body(head, buffer)

        case (.body(let head, var buffer), .body(var chunk)):
            buffer.writeBuffer(&chunk)
            if buffer.readableBytes >= expectedLength(head) {
                beginRelay(context: context, head: head, body: buffer)
            } else {
                state = .body(head, buffer)
            }

        case (.body(let head, let buffer), .end):
            if buffer.readableBytes >= expectedLength(head) {
                beginRelay(context: context, head: head, body: buffer)
            } else {
                reject(context: context, status: .badRequest, message: "incomplete body")
                state = .done
            }

        default:
            break
        }
    }

    private func expectedLength(_ head: HTTPRequestHead) -> Int {
        Int(head.headers["content-length"].first ?? "0") ?? 0
    }

    private func beginRelay(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer) {
        state = .relaying
        self.relayContext = context
        let channel = context.channel
        let requestID = String(UUID().uuidString.prefix(8)).lowercased()
        let bodyData = Data(body.readableBytesView)
        let meta = RequestInspector.meta(head: head, body: bodyData)
        Log.info("Gateway [" + requestID + "] " + head.method.rawValue + " " + head.uri + " model=" + (meta.model ?? "?"))

        let task = Task {
            await Self.relay(channel: channel, head: head, body: bodyData, meta: meta, config: self.config, collector: self.collector, requestID: requestID) { part in
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    channel.eventLoop.execute {
                        guard let ctx = self.relayContext else {
                            cont.resume()
                            return
                        }
                        ctx.write(self.wrapOutboundOut(part), promise: nil)
                        ctx.flush()
                        cont.resume()
                    }
                }
            }
            channel.eventLoop.execute {
                self.relayContext = nil
                channel.close(mode: .all, promise: nil)
            }
        }
        channel.closeFuture.whenComplete { _ in task.cancel() }
    }

    private func reject(context: ChannelHandlerContext, status: HTTPResponseStatus, message: String) {
        var head = HTTPResponseHead(version: .http1_1, status: status)
        head.headers.add(name: "content-type", value: "text/plain; charset=utf-8")
        head.headers.add(name: "connection", value: "close")
        let body = context.channel.allocator.buffer(string: message)
        head.headers.add(name: "content-length", value: String(body.readableBytes))
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }

    // MARK: - Relay (runs off the event loop)

    private static func relay(
        channel: Channel,
        head: HTTPRequestHead,
        body: Data,
        meta: RequestMeta,
        config: GatewayConfig,
        collector: UsageCollector,
        requestID: String,
        writePart: @escaping (HTTPServerResponsePart) async -> Void
    ) async {
        do {
            let response = try await GatewayRequestForwarder.forward(head: head, body: body, config: config)
            switch response {
            case .complete(let status, let contentType, let payload):
                var responseHead = HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: status))
                responseHead.headers.add(name: "content-type", value: contentType)
                responseHead.headers.add(name: "content-length", value: String(payload.count))
                responseHead.headers.add(name: "connection", value: "close")
                await writePart(.head(responseHead))
                await writePart(.body(.byteBuffer(channel.allocator.buffer(bytes: payload))))
                await writePart(.end(nil))

                let usage = UsageExtractor.usage(fromJSON: payload)
                await collector.record(apiKey: meta.apiKey, model: meta.model, usage: usage, at: Date())

            case .stream(let status, let contentType, let bytes):
                var responseHead = HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: status))
                responseHead.headers.add(name: "content-type", value: contentType)
                responseHead.headers.add(name: "transfer-encoding", value: "chunked")
                responseHead.headers.add(name: "connection", value: "close")
                await writePart(.head(responseHead))

                var parser = StreamUsageParser()
                var usage: GatewayUsage?
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        let chunk = line + "\n"
                        await writePart(.body(.byteBuffer(channel.allocator.buffer(string: chunk))))
                        parser.appendLine(chunk)
                    }
                    parser.finish()
                    usage = parser.usage
                    await writePart(.end(nil))
                } catch {
                    Log.info("Gateway [" + requestID + "] stream ended early (client disconnect or upstream error)")
                    try? await writePart(.end(nil))
                }
                await collector.record(apiKey: meta.apiKey, model: meta.model, usage: usage, at: Date())
            }
        } catch let error as GatewayError {
            Log.error("Gateway [" + requestID + "] relay failed: " + (error.errorDescription ?? "gateway error"))
            await writeError(channel: channel, status: .badGateway, message: error.errorDescription ?? "gateway error", writePart: writePart)
        } catch let error as DeepSeekError {
            Log.error("Gateway [" + requestID + "] upstream error: " + (error.errorDescription ?? "upstream"))
            await writeError(channel: channel, status: .badGateway, message: error.errorDescription ?? "upstream error", writePart: writePart)
        } catch {
            Log.error("Gateway [" + requestID + "] relay failed (sanitized): " + Log.sanitize(error.localizedDescription))
            await writeError(channel: channel, status: .badGateway, message: "gateway error", writePart: writePart)
        }
    }

    private static func writeError(channel: Channel, status: HTTPResponseStatus, message: String, writePart: @escaping (HTTPServerResponsePart) async -> Void) async {
        var head = HTTPResponseHead(version: .http1_1, status: status)
        head.headers.add(name: "content-type", value: "text/plain; charset=utf-8")
        head.headers.add(name: "connection", value: "close")
        let body = channel.allocator.buffer(string: message)
        head.headers.add(name: "content-length", value: String(body.readableBytes))
        await writePart(.head(head))
        await writePart(.body(.byteBuffer(body)))
        await writePart(.end(nil))
    }
}
