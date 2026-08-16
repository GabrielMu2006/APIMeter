import Foundation
import Testing
@testable import APIMeterCore

struct BalanceDecodingTests {

    @Test func decodesOfficialBalanceResponse() throws {
        let json = """
        {"is_available": true, "balance_infos": [{"currency": "CNY", "total_balance": "110.00", "granted_balance": "10.00", "topped_up_balance": "100.00"}]}
        """.data(using: .utf8)!
        let raw = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: json)
        let balance = try DeepSeekClient.mapBalance(raw)
        #expect(balance.isAvailable)
        #expect(balance.balanceInfos.count == 1)
        #expect(balance.balanceInfos[0].totalBalance == Decimal(string: "110.00"))
        #expect(balance.balanceInfos[0].currency == "CNY")
    }

    @Test func rejectsUnparseableAmounts() throws {
        let json = """
        {"is_available": true, "balance_infos": [{"currency": "CNY", "total_balance": "abc", "granted_balance": "1", "topped_up_balance": "2"}]}
        """.data(using: .utf8)!
        let raw = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: json)
        #expect(throws: DeepSeekError.self) {
            _ = try DeepSeekClient.mapBalance(raw)
        }
    }
}
