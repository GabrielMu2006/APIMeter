import Foundation
import Testing
import Foundation
import APIMeterCore

struct StreamUsageParserTests {

    @Test func extractsUsageFromFinalChunk() {
        var parser = StreamUsageParser()
        parser.appendLine("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}")
        parser.appendLine("")
        parser.appendLine("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":34,\"total_tokens\":46,\"prompt_cache_hit_tokens\":5,\"prompt_cache_miss_tokens\":7}}")
        parser.finish()
        #expect(parser.usage?.totalTokens == 46)
        #expect(parser.usage?.cacheHitTokens == 5)
    }

    @Test func lastUsageWins() {
        var parser = StreamUsageParser()
        parser.appendLine("data: {\"usage\":{\"total_tokens\":1}}")
        parser.appendLine("data: {\"usage\":{\"total_tokens\":99}}")
        parser.finish()
        #expect(parser.usage?.totalTokens == 99)
    }

    @Test func noUsageStaysNil() {
        var parser = StreamUsageParser()
        parser.appendLine("data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}")
        parser.appendLine("data: [DONE]")
        parser.finish()
        #expect(parser.usage == nil)
    }
}
