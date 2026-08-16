import Foundation

/// Usage object as reported by DeepSeek in a response or a stream chunk.
public struct GatewayUsage: Equatable, Sendable {
    public let promptTokens: Int64?
    public let completionTokens: Int64?
    public let totalTokens: Int64?
    public let cacheHitTokens: Int64?
    public let cacheMissTokens: Int64?

    /// Returns nil when the dict carries no token information at all.
    public init?(from dict: [String: Any]) {
        let prompt = Self.int(dict, "prompt_tokens")
        let completion = Self.int(dict, "completion_tokens")
        let total = Self.int(dict, "total_tokens")
        let hit = Self.int(dict, "prompt_cache_hit_tokens")
        let miss = Self.int(dict, "prompt_cache_miss_tokens")
        if prompt == nil && completion == nil && total == nil && hit == nil && miss == nil {
            return nil
        }
        self.promptTokens = prompt
        self.completionTokens = completion
        self.totalTokens = total
        self.cacheHitTokens = hit
        self.cacheMissTokens = miss
    }

    private static func int(_ dict: [String: Any], _ key: String) -> Int64? {
        guard let value = dict[key] else { return nil }
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}

/// Incremental SSE parser for streamed chat completions.
/// Extracts the LAST non-null usage object seen in data: chunks.
/// It never retains prompt/completion content - usage only (spec 21).
public struct StreamUsageParser: Sendable {
    private var buffer = Data()
    public private(set) var usage: GatewayUsage?

    public init() {}

    public mutating func appendLine(_ line: String) {
        processLine(line)
    }

    public mutating func finish() {
        if !buffer.isEmpty {
            processLine(String(data: buffer, encoding: .utf8) ?? "")
            buffer.removeAll()
        }
    }

    private mutating func processLine(_ raw: String) {
        var line = raw
        if line.hasSuffix("\r") { line.removeLast() }
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usageDict = obj["usage"] as? [String: Any],
              let parsed = GatewayUsage(from: usageDict) else { return }
        self.usage = parsed
    }
}
