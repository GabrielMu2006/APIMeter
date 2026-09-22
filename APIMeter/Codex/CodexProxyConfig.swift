import CFNetwork
import Foundation

/// User-configured proxy for the Codex usage request (settings: "Use proxy
/// for Codex requests"). URLSession ignores environment-variable proxies
/// (https_proxy only reaches child processes), so routing its traffic through
/// a local proxy needs an explicit connectionProxyDictionary.
public struct CodexProxyConfig: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case http
        case socks
    }

    public let kind: Kind
    public let host: String
    public let port: Int

    public init(kind: Kind, host: String, port: Int) {
        self.kind = kind
        self.host = host
        self.port = port
    }

    /// Parses "http://127.0.0.1:8080", "127.0.0.1:8080" (scheme optional,
    /// http assumed) and "socks5://127.0.0.1:7890". A port is required;
    /// returns nil on anything unparseable so callers can fall back to a
    /// direct connection and the UI can flag the address as invalid.
    public static func parse(_ raw: String) -> CodexProxyConfig? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var kind: Kind = .http
        if let schemeRange = text.range(of: "://") {
            switch text[..<schemeRange.lowerBound].lowercased() {
            case "http", "https": kind = .http
            case "socks5", "socks5h", "socks4": kind = .socks
            default: return nil
            }
            text = String(text[schemeRange.upperBound...])
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let host = String(text[..<colon])
        let portText = text[text.index(after: colon)...]
        guard !host.isEmpty, !host.contains("@"), let port = Int(portText),
              (1...65535).contains(port) else { return nil }
        return CodexProxyConfig(kind: kind, host: host, port: port)
    }

    /// Proxy dictionary for URLSessionConfiguration. HTTP CONNECT covers
    /// https traffic; SOCKS uses the documented SC schema keys.
    public var connectionProxyDictionary: [AnyHashable: Any] {
        switch kind {
        case .http:
            return [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        case .socks:
            return [
                "SOCKSEnable": true,
                "SOCKSProxy": host,
                "SOCKSPort": port,
            ]
        }
    }
}
