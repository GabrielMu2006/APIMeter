import Foundation
import NIOHTTP1

/// Result of an upstream forward operation.
enum UpstreamResponse {
    /// Fully buffered (non-streaming) response.
    case complete(status: Int, contentType: String, payload: Data)
    /// Streaming response, relayed line-by-line without full buffering.
    case stream(status: Int, contentType: String, bytes: URLSession.AsyncBytes)
}

/// Metadata extracted from a request - used for usage recording only.
/// NEVER stored or logged in raw form (spec 21/86).
struct RequestMeta: Sendable {
    let apiKey: String?
    let model: String?
    let isStream: Bool
}

enum RequestInspector {
    static func meta(head: HTTPRequestHead, body: Data) -> RequestMeta {
        var apiKey: String?
        if let auth = head.headers["authorization"].first,
           auth.lowercased().hasPrefix("bearer ") {
            apiKey = String(auth.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var model: String?
        var isStream = false
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            model = obj["model"] as? String
            isStream = (obj["stream"] as? Bool) ?? false
        }
        return RequestMeta(apiKey: apiKey, model: model, isStream: isStream)
    }
}

/// Forwards a request upstream to DeepSeek. The request body and parameters
/// are passed through UNMODIFIED (spec 21 - transparent forwarding only).
enum GatewayRequestForwarder {

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 1200
        return URLSession(configuration: configuration)
    }()

    static func forward(head: HTTPRequestHead, body: Data, config: GatewayConfig) async throws -> UpstreamResponse {
        guard let url = URL(string: head.uri, relativeTo: config.upstreamBaseURL)?.absoluteURL else {
            throw GatewayError.invalidRequest
        }
        var request = URLRequest(url: url)
        request.httpMethod = head.method.rawValue

        // Transparent header forwarding - strip hop-by-hop headers only.
        let skip = ["host", "content-length", "connection", "accept-encoding", "transfer-encoding", "proxy-connection", "te", "trailer", "upgrade"]
        for (name, value) in head.headers {
            guard !skip.contains(name.lowercased()) else { continue }
            request.setValue(value, forHTTPHeaderField: name)
        }
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let isStream = RequestInspector.meta(head: head, body: body).isStream
        if isStream {
            let (bytes, response) = try await Self.session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DeepSeekError.invalidResponse("upstream response is not HTTP")
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "text/event-stream; charset=utf-8"
            return .stream(status: http.statusCode, contentType: contentType, bytes: bytes)
        } else {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DeepSeekError.invalidResponse("upstream response is not HTTP")
            }
            guard data.count <= config.maxResponseBodyBytes else {
                throw DeepSeekError.invalidResponse("upstream response too large")
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "application/json"
            return .complete(status: http.statusCode, contentType: contentType, payload: data)
        }
    }
}

/// Parses DeepSeek usage objects (non-stream JSON responses and stream chunks).
enum UsageExtractor {

    /// Reads the usage object from a complete (non-stream) response body.
    /// DeepSeek usage keys: prompt_tokens, completion_tokens, total_tokens,
    /// prompt_cache_hit_tokens, prompt_cache_miss_tokens.
    static func usage(fromJSON data: Data) -> GatewayUsage? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usageDict = obj["usage"] as? [String: Any] else { return nil }
        return GatewayUsage(from: usageDict)
    }
}
