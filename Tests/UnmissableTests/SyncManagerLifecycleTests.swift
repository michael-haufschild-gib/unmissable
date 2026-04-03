@testable import Unmissable
import XCTest

@MainActor
final class SyncManagerLifecycleTests: XCTestCase {
    private var manager: SyncManager!
    private var databaseManager: DatabaseManager!
    private var tempDatabaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        let tempDir = FileManager.default.temporaryDirectory
        tempDatabaseURL = tempDir.appendingPathComponent(
            "unmissable-synclifecycle-\(UUID().uuidString).db",
        )
        databaseManager = DatabaseManager(databaseURL: tempDatabaseURL)

        let preferences = PreferencesManager(themeManager: ThemeManager())
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())
        manager = SyncManager(
            apiService: apiService,
            databaseManager: databaseManager,
            preferencesManager: preferences,
        )
    }

    override func tearDown() async throws {
        manager?.stopPeriodicSync()
        manager = nil
        databaseManager = nil
        if let url = tempDatabaseURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempDatabaseURL = nil
        try await super.tearDown()
    }

    func testStopPeriodicSync_resetsRetryCount() {
        manager.retryCount = 3

        manager.stopPeriodicSync()

        XCTAssertEqual(manager.retryCount, 0, "Stopping periodic sync should clear retry state")
    }

    func testStopPeriodicSync_resetsRetryCountRegardlessOfValue() {
        manager.retryCount = 10

        manager.stopPeriodicSync()

        XCTAssertEqual(manager.retryCount, 0, "Stopping should reset even high retry counts")
    }

    func testInitialRetryCountIsZero() {
        XCTAssertEqual(manager.retryCount, 0, "New SyncManager should have 0 retry count")
    }

    func testInitialSyncStatusIsIdle() {
        XCTAssertEqual(manager.syncStatus, .idle)
    }

    func testInitialLastSyncTimeIsNil() {
        XCTAssertNil(manager.lastSyncTime, "New SyncManager should have nil lastSyncTime")
    }

    func testPerformSync_whenNoCalendarsSelected_completesWithoutUpdatingLastSync() async {
        await manager.performSync()

        // Without calendars selected, sync may return idle or error depending on auth state.
        // The key invariant: lastSyncTime should not be set on a failed or no-op sync.
        XCTAssertNil(
            manager.lastSyncTime,
            "No-op or failed sync should not update lastSyncTime",
        )
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
            updatedAt: Date(),
        )
        try await databaseManager.saveCalendars([calendar])

        await manager.performSync()

        // With selected calendars but no valid OAuth state, fetchEvents fails
        // → SyncManager catches the error → sets .error status.
        XCTAssertTrue(
            manager.syncStatus.isError,
            "Sync with selected calendars but no auth should set error status, got: \(manager.syncStatus)",
        )
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
            updatedAt: Date(),
        )
        try await databaseManager.saveCalendars([calendar])

        // Force SyncManager into the failing path:
        // authenticated flag true, but no valid OAuth token/state available.
        let oauth2Service = OAuth2Service()
        oauth2Service.isAuthenticated = true
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())
        let preferences = PreferencesManager(themeManager: ThemeManager())
        manager.stopPeriodicSync()
        manager = SyncManager(
            apiService: apiService,
            databaseManager: databaseManager,
            preferencesManager: preferences,
        )

        await manager.performSync()

        if case .error = manager.syncStatus {
            // Expected failure path.
        } else {
            XCTFail("Expected sync to fail and set error status")
        }

        XCTAssertNil(
            manager.lastSyncTime,
            "Failed sync attempts should not advance last successful sync timestamp",
        )
    }
}
