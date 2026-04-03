@testable import Unmissable
import XCTest

final class SyncStatusTests: XCTestCase {
    // MARK: - isSyncing

    func testIsSyncing_trueOnlyForSyncingCase() {
        XCTAssertTrue(SyncStatus.syncing.isSyncing)
        XCTAssertFalse(SyncStatus.idle.isSyncing)
        XCTAssertFalse(SyncStatus.offline.isSyncing)
        XCTAssertFalse(SyncStatus.error("fail").isSyncing)
    }

    // MARK: - isError

    func testIsError_trueOnlyForErrorCase() {
        XCTAssertTrue(SyncStatus.error("timeout").isError)
        XCTAssertTrue(SyncStatus.error("").isError)
        XCTAssertFalse(SyncStatus.idle.isError)
        XCTAssertFalse(SyncStatus.syncing.isError)
        XCTAssertFalse(SyncStatus.offline.isError)
    }

    // MARK: - Equatable

    func testEquatable_sameValueCasesAreEqual() {
        XCTAssertEqual(SyncStatus.idle, SyncStatus.idle)
        XCTAssertEqual(SyncStatus.syncing, SyncStatus.syncing)
        XCTAssertEqual(SyncStatus.offline, SyncStatus.offline)
        XCTAssertEqual(SyncStatus.error("timeout"), SyncStatus.error("timeout"))
    }

    func testEquatable_differentCasesAreNotEqual() {
        XCTAssertNotEqual(SyncStatus.idle, SyncStatus.syncing)
        XCTAssertNotEqual(SyncStatus.idle, SyncStatus.offline)
        XCTAssertNotEqual(SyncStatus.syncing, SyncStatus.error("x"))
    }

    func testEquatable_errorWithDifferentMessagesAreNotEqual() {
        XCTAssertNotEqual(
            SyncStatus.error("timeout"),
            SyncStatus.error("network"),
            "Error cases with different messages should not be equal",
        )
    }

    // MARK: - Description

    func testDescription_emptyErrorMessageStillFormatsCorrectly() {
        XCTAssertEqual(SyncStatus.error("").description, "Error: ")
    }

    func testDescription_errorMessageWithSpecialCharacters() {
        let status = SyncStatus.error("OAuth token expired: 401")
        XCTAssertEqual(status.description, "Error: OAuth token expired: 401")
    }
}
