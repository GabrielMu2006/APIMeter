import XCTest
@testable import APIMeter

@MainActor
final class AppStateTests: XCTestCase {

    /// Regression test: the day-detail sheet must be closeable.
    /// It is bound to AppState.selectedDay; the Done (X) button / Esc calls
    /// closeDayDetail(), which must clear it so the sheet dismisses.
    func testDayDetailCanBeClosed() throws {
        let state = try AppState(environment: .ephemeral())
        state.selectedDay = LocalDay("2026-08-21")!
        XCTAssertNotNil(state.selectedDay)

        state.closeDayDetail()

        XCTAssertNil(state.selectedDay, "closeDayDetail() must clear selectedDay so the sheet closes")
    }

    /// Opening a day detail sets the day; the sheet can then be closed again.
    func testDayDetailOpenThenCloseRoundTrip() throws {
        let state = try AppState(environment: .ephemeral())
        state.selectedDay = LocalDay("2026-08-20")!
        XCTAssertNotNil(state.selectedDay)
        state.closeDayDetail()
        XCTAssertNil(state.selectedDay)
    }
}
