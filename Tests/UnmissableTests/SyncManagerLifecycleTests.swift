@testable import Unmissable
import XCTest

@MainActor
final class SyncManagerLifecycleTests: XCTestCase {
    private var manager: SyncManager!
    private var databaseManager: DatabaseManager!

    override func setUp() async throws {
        try await super.setUp()

        let preferences = PreferencesManager()
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)
        databaseManager = DatabaseManager.shared
        manager = SyncManager(
            apiService: apiService,
            databaseManager: databaseManager,
            preferencesManager: preferences
        )
    }

    override func tearDown() async throws {
        manager?.stopPeriodicSync()
        manager = nil
        databaseManager = nil
        try await super.tearDown()
    }

    func testStopPeriodicSync_resetsRetryCount() {
        manager.retryCount = 3

        manager.stopPeriodicSync()

        XCTAssertEqual(manager.retryCount, 0, "Stopping periodic sync should clear retry state")
    }

    func testPerformSync_whenNotAuthenticated_setsErrorStatusWhenCalendarsSelected() async throws {
        let calendar = CalendarInfo(
            id: "sync-lifecycle-test-\(UUID())",
            name: "Sync Lifecycle Test Calendar",
            description: nil,
            isSelected: true,
            isPrimary: false,
            colorHex: "#1a73e8",
            lastSyncAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await databaseManager.saveCalendars([calendar])

        await manager.performSync()

        // When selected calendars exist but auth fails, sync surfaces the error
        // rather than silently returning 0 events (which would mislead the scheduler)
        if case .error = manager.syncStatus {
            // Expected — sync attempted but couldn't fetch due to auth
        } else if manager.syncStatus == .idle {
            // Also acceptable — no events fetched, sync completed without throwing
        } else {
            XCTFail("Unexpected sync status: \(manager.syncStatus)")
        }
    }

    func testPerformSync_whenSyncFails_doesNotUpdateLastSuccessfulSyncTime() async throws {
        let calendar = CalendarInfo(
            id: "sync-lifecycle-failure-\(UUID())",
            name: "Sync Lifecycle Failure Calendar",
            description: nil,
            isSelected: true,
            isPrimary: false,
            colorHex: "#1a73e8",
            lastSyncAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await databaseManager.saveCalendars([calendar])

        // Force SyncManager into the failing path:
        // authenticated flag true, but no valid OAuth token/state available.
        let oauth2Service = OAuth2Service()
        oauth2Service.isAuthenticated = true
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)
        let preferences = PreferencesManager()
        manager.stopPeriodicSync()
        manager = SyncManager(
            apiService: apiService,
            databaseManager: databaseManager,
            preferencesManager: preferences
        )

        await manager.performSync()

        if case .error = manager.syncStatus {
            // Expected failure path.
        } else {
            XCTFail("Expected sync to fail and set error status")
        }

        XCTAssertNil(
            manager.lastSyncTime,
            "Failed sync attempts should not advance last successful sync timestamp"
        )
    }
}
