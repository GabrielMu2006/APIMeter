import Foundation
import Testing
@testable import APIMeterCore

/// Codex proxy setting: address parsing (http/socks, optional scheme,
/// required port) and the connectionProxyDictionary that routes the usage
/// request through it.
struct CodexProxyConfigTests {

    @Test func parsesHttpProxyWithScheme() throws {
        let proxy = try #require(CodexProxyConfig.parse("http://127.0.0.1:8080"))
        #expect(proxy == CodexProxyConfig(kind: .http, host: "127.0.0.1", port: 8080))
    }

    @Test func schemeIsOptionalAndDefaultsToHttp() throws {
        let proxy = try #require(CodexProxyConfig.parse("127.0.0.1:8080"))
        #expect(proxy.kind == .http)
        #expect(proxy.host == "127.0.0.1")
        #expect(proxy.port == 8080)
    }

    @Test func parsesSocksProxy() throws {
        for scheme in ["socks5", "socks5h", "socks4"] {
            let proxy = try #require(CodexProxyConfig.parse(scheme + "://127.0.0.1:7890"))
            #expect(proxy.kind == .socks)
            #expect(proxy.port == 7890)
        }
    }

    @Test func toleratesWhitespaceTrailingSlashAndCase() throws {
        let proxy = try #require(CodexProxyConfig.parse("  HTTP://LocalHost:8080/  "))
        #expect(proxy == CodexProxyConfig(kind: .http, host: "LocalHost", port: 8080))
    }

    @Test func rejectsUnusableAddresses() {
        #expect(CodexProxyConfig.parse("") == nil)
        #expect(CodexProxyConfig.parse("   ") == nil)
        #expect(CodexProxyConfig.parse("http://127.0.0.1") == nil) // no port
        #expect(CodexProxyConfig.parse("127.0.0.1") == nil) // no port
        #expect(CodexProxyConfig.parse("http://127.0.0.1:0") == nil) // port range
        #expect(CodexProxyConfig.parse("http://127.0.0.1:70000") == nil)
        #expect(CodexProxyConfig.parse("http://:8080") == nil) // no host
        #expect(CodexProxyConfig.parse("http://user:pass@127.0.0.1:8080") == nil) // userinfo
        #expect(CodexProxyConfig.parse("ftp://127.0.0.1:8080") == nil) // unknown scheme
    }

    @Test func httpProxyDictionaryEnablesBothSchemes() throws {
        let proxy = try #require(CodexProxyConfig.parse("http://127.0.0.1:8080"))
        let dict = proxy.connectionProxyDictionary as! [String: Any]
        #expect(dict["HTTPEnable"] as? Bool == true)
        #expect(dict["HTTPProxy"] as? String == "127.0.0.1")
        #expect(dict["HTTPPort"] as? Int == 8080)
        #expect(dict["HTTPSEnable"] as? Bool == true)
        #expect(dict["HTTPSProxy"] as? String == "127.0.0.1")
        #expect(dict["HTTPSPort"] as? Int == 8080)
    }

    @Test func socksProxyDictionaryUsesSchemaKeys() throws {
        let proxy = try #require(CodexProxyConfig.parse("socks5://127.0.0.1:7890"))
        let dict = proxy.connectionProxyDictionary as! [String: Any]
        #expect(dict["SOCKSEnable"] as? Bool == true)
        #expect(dict["SOCKSProxy"] as? String == "127.0.0.1")
        #expect(dict["SOCKSPort"] as? Int == 7890)
        #expect(dict["HTTPEnable"] == nil)
    }
}
