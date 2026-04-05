import Foundation
import Testing
@testable import Unmissable

@MainActor
struct SyncManagerLifecycleTests {
    private let manager: SyncManager
    private let databaseManager: DatabaseManager
    private let tempDatabaseURL: URL

    init() {
        let tempDir = FileManager.default.temporaryDirectory
        tempDatabaseURL = tempDir.appendingPathComponent(
            "unmissable-synclifecycle-\(UUID().uuidString).db",
        )
        databaseManager = DatabaseManager(databaseURL: tempDatabaseURL)

        let preferences = PreferencesManager(themeManager: ThemeManager())
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())
        manager = SyncManager(
            providerType: .google,
            apiService: apiService,
            databaseManager: databaseManager,
            preferencesManager: preferences,
        )
    }

    @Test
    func stopPeriodicSync_resetsRetryCount() {
        defer { manager.stopPeriodicSync() }
        manager.retryCount = 3

        manager.stopPeriodicSync()

        #expect(manager.retryCount == 0, "Stopping periodic sync should clear retry state")
    }

    @Test
    func stopPeriodicSync_resetsRetryCountRegardlessOfValue() {
        defer { manager.stopPeriodicSync() }
        manager.retryCount = 10

        manager.stopPeriodicSync()

        #expect(manager.retryCount == 0, "Stopping should reset even high retry counts")
    }

    @Test
    func initialRetryCountIsZero() {
        defer { manager.stopPeriodicSync() }
        #expect(manager.retryCount == 0, "New SyncManager should have 0 retry count")
    }

    @Test
    func initialSyncStatusIsIdle() {
        defer { manager.stopPeriodicSync() }
        #expect(manager.syncStatus == .idle)
    }

    @Test
    func initialLastSyncTimeIsNil() {
        defer { manager.stopPeriodicSync() }
        #expect(manager.lastSyncTime == nil, "New SyncManager should have nil lastSyncTime")
    }

    @Test
    func performSync_whenNoCalendarsSelected_completesWithoutUpdatingLastSync() async {
        defer { manager.stopPeriodicSync() }
        await manager.performSync()

        // Without calendars selected, sync may return idle or error depending on auth state.
        // The key invariant: lastSyncTime should not be set on a failed or no-op sync.
        #expect(
            manager.lastSyncTime == nil,
            "No-op or failed sync should not update lastSyncTime",
        )
    }

    @Test
    func performSync_whenNotAuthenticated_setsErrorStatusWhenCalendarsSelected() async throws {
        defer { manager.stopPeriodicSync() }
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
        #expect(
            manager.syncStatus.isError,
            "Sync with selected calendars but no auth should set error status, got: \(manager.syncStatus)",
        )
    }

    @Test
    func performSync_whenSyncFails_doesNotUpdateLastSuccessfulSyncTime() async throws {
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
        let failingManager = SyncManager(
            providerType: .google,
            apiService: apiService,
            databaseManager: databaseManager,
            preferencesManager: preferences,
        )
        defer { failingManager.stopPeriodicSync() }

        await failingManager.performSync()

        if case .error = failingManager.syncStatus {
            // Expected failure path.
        } else {
            Issue.record("Expected sync to fail and set error status")
        }

        #expect(
            failingManager.lastSyncTime == nil,
            "Failed sync attempts should not advance last successful sync timestamp",
        )
    }
}
