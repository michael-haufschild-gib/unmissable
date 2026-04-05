import Foundation
import Testing
@testable import Unmissable

struct SyncStatusTests {
    // MARK: - isSyncing

    @Test
    func isSyncing_trueOnlyForSyncingCase() {
        #expect(SyncStatus.syncing.isSyncing)
        #expect(!SyncStatus.idle.isSyncing)
        #expect(!SyncStatus.offline.isSyncing)
        #expect(!SyncStatus.error("fail").isSyncing)
    }

    // MARK: - isError

    @Test
    func isError_trueOnlyForErrorCase() {
        #expect(SyncStatus.error("timeout").isError)
        #expect(SyncStatus.error("").isError)
        #expect(!SyncStatus.idle.isError)
        #expect(!SyncStatus.syncing.isError)
        #expect(!SyncStatus.offline.isError)
    }

    // MARK: - Equatable

    @Test
    func equatable_sameValueCasesAreEqual() {
        let idle = SyncStatus.idle
        let syncing = SyncStatus.syncing
        let offline = SyncStatus.offline
        #expect(idle == .idle)
        #expect(syncing == .syncing)
        #expect(offline == .offline)
        let errorA = SyncStatus.error("timeout")
        #expect(errorA == .error("timeout"))
    }

    @Test
    func equatable_differentCasesAreNotEqual() {
        #expect(SyncStatus.idle != SyncStatus.syncing)
        #expect(SyncStatus.idle != SyncStatus.offline)
        #expect(SyncStatus.syncing != SyncStatus.error("x"))
    }

    @Test
    func equatable_errorWithDifferentMessagesAreNotEqual() {
        #expect(
            SyncStatus.error("timeout") != SyncStatus.error("network"),
            "Error cases with different messages should not be equal",
        )
    }

    // MARK: - Description

    @Test
    func description_emptyErrorMessageStillFormatsCorrectly() {
        #expect(SyncStatus.error("").description == "Error: ")
    }

    @Test
    func description_errorMessageWithSpecialCharacters() {
        let status = SyncStatus.error("OAuth token expired: 401")
        #expect(status.description == "Error: OAuth token expired: 401")
    }
}
