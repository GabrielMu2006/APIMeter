import XCTest
@testable import APIMeter

@MainActor
final class CLIProtocolTests: XCTestCase {

    func testParsesSuccessJSON() {
        let out = SyncScheduler.parseCLIOutput(
            #"{"ok":true,"file":"usage.zip","path":"/tmp/usage.zip","bytes":123,"sha256":"ABC123"}"#
        )
        XCTAssertEqual(out?.ok, true)
        XCTAssertEqual(out?.path, "/tmp/usage.zip")
        XCTAssertEqual(out?.sha256, "ABC123")
    }

    func testParsesFailureJSONWithSessionExpired() {
        let out = SyncScheduler.parseCLIOutput(
            #"{"ok":false,"sessionExpired":true,"error":"DeepSeek session expired. Please login again."}"#
        )
        XCTAssertEqual(out?.ok, false)
        XCTAssertEqual(out?.sessionExpired, true)
        XCTAssertNotNil(out?.error)
    }

    func testRejectsGarbage() {
        XCTAssertNil(SyncScheduler.parseCLIOutput("not json at all"))
        XCTAssertNil(SyncScheduler.parseCLIOutput(""))
    }
}
