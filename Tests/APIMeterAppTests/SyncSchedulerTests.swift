import XCTest
@testable import APIMeter

@MainActor
final class SyncSchedulerTests: XCTestCase {

    /// P0-1 regression: the scheduler must be strongly owned by AppState.
    /// With a weak reference it would deallocate right after launch and the
    /// daily sync would silently stop running.
    func testSyncSchedulerIsStronglyOwned() throws {
        let state = try AppState(environment: .ephemeral())
        var scheduler: SyncScheduler? = SyncScheduler(environment: state.environment)
        state.syncScheduler = scheduler
        scheduler = nil
        XCTAssertNotNil(state.syncScheduler, "AppState must keep the scheduler alive (weak would nil it here)")
    }

    /// P0-2: only duplicateFile is benign; every other ImportError must stay
    /// a failure so the day retries.
    func testOnlyDuplicateFileIsBenignImportError() {
        XCTAssertTrue(SyncScheduler.isBenignImportError(.duplicateFile(filename: "x.zip")))
        XCTAssertFalse(SyncScheduler.isBenignImportError(.unsupportedSchema(details: "boom")))
        XCTAssertFalse(SyncScheduler.isBenignImportError(.emptyFile))
        XCTAssertFalse(SyncScheduler.isBenignImportError(.zipExtractionFailed("boom")))
        XCTAssertFalse(SyncScheduler.isBenignImportError(.tooManyFiles(999)))
        XCTAssertFalse(SyncScheduler.isBenignImportError(.fileTooLarge(999)))
        XCTAssertFalse(SyncScheduler.isBenignImportError(.invalidDay("nope")))
    }
}
