@testable import Unmissable
import XCTest

// MARK: - Mock Calendar Auth Provider

@MainActor
final class MockCalendarAuthProvider: CalendarAuthProviding {
    var isAuthenticated: Bool = false
    var userEmail: String?
    var authorizationError: String?

    var startAuthorizationFlowHandler: (() async throws -> Void)?

    func startAuthorizationFlow() async throws {
        if let handler = startAuthorizationFlowHandler {
            try await handler()
        }
        isAuthenticated = true
    }

    func validateAuthState() async {
        // No-op for tests
    }

    func signOut() {
        isAuthenticated = false
        userEmail = nil
    }
}

// MARK: - Mock Calendar API Provider

@MainActor
final class MockCalendarAPIProvider: CalendarAPIProviding {
    var calendars: [CalendarInfo] = []
    var events: [Event] = []
    var lastError: String?

    func fetchCalendars() async -> [CalendarInfo] {
        calendars
    }

    func fetchEvents(for _: [String], from _: Date, to _: Date) async -> [Event] {
        events
    }
}

// MARK: - Multi-Provider Integration Tests

@MainActor
final class MultiProviderIntegrationTests: XCTestCase {
    private var calendarService: CalendarService!
    private var preferencesManager: PreferencesManager!
    private var databaseManager: DatabaseManager!
    private var tempDatabaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        let tempDir = FileManager.default.temporaryDirectory
        tempDatabaseURL = tempDir.appendingPathComponent(
            "unmissable-multiprovider-\(UUID().uuidString).db"
        )
        databaseManager = DatabaseManager(databaseURL: tempDatabaseURL)
        preferencesManager = PreferencesManager(themeManager: ThemeManager())
        calendarService = CalendarService(
            preferencesManager: preferencesManager,
            databaseManager: databaseManager,
            linkParser: LinkParser()
        )
    }

    override func tearDown() async throws {
        calendarService = nil
        preferencesManager = nil
        databaseManager = nil
        if let url = tempDatabaseURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempDatabaseURL = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Creates and injects a mock backend for a given provider type, returning the mock auth/API
    /// so the test can manipulate state after injection.
    @discardableResult
    private func injectProvider(
        _ type: CalendarProviderType,
        authenticated: Bool = true,
        email: String? = nil,
        authError: String? = nil
    ) -> (auth: MockCalendarAuthProvider, api: MockCalendarAPIProvider, sync: SyncManager) {
        let auth = MockCalendarAuthProvider()
        auth.isAuthenticated = authenticated
        auth.userEmail = email
        auth.authorizationError = authError

        let api = MockCalendarAPIProvider()

        let sync = SyncManager(
            apiService: api,
            databaseManager: databaseManager,
            preferencesManager: preferencesManager
        )

        calendarService.injectTestBackend(type: type, auth: auth, api: api, sync: sync)
        return (auth, api, sync)
    }

    // MARK: - Two Providers Connected

    func testConnectingTwoProvidersReportsBothInConnectedProviders() {
        injectProvider(.google, authenticated: true, email: "user@gmail.com")
        injectProvider(.apple, authenticated: true)

        XCTAssertEqual(calendarService.connectedProviders, Set([.google, .apple]))
        XCTAssertTrue(calendarService.isConnected)
        XCTAssertEqual(calendarService.userEmail, "user@gmail.com")
    }

    // MARK: - Disconnect One Provider

    func testDisconnectingOneProviderLeavesOtherConnected() {
        injectProvider(.google, authenticated: true, email: "user@gmail.com")
        injectProvider(.apple, authenticated: true)

        XCTAssertEqual(calendarService.connectedProviders, Set([.google, .apple]))

        calendarService.removeTestBackend(type: .google)

        XCTAssertEqual(calendarService.connectedProviders, Set([.apple]))
        XCTAssertTrue(calendarService.isConnected)
        XCTAssertNil(calendarService.userEmail, "Email should clear when Google is disconnected")
    }

    func testDisconnectingBothProvidersReportsDisconnected() {
        injectProvider(.google, authenticated: true)
        injectProvider(.apple, authenticated: true)

        calendarService.removeTestBackend(type: .google)
        calendarService.removeTestBackend(type: .apple)

        XCTAssertEqual(calendarService.connectedProviders, Set<CalendarProviderType>())
        XCTAssertFalse(calendarService.isConnected)
    }

    // MARK: - Aggregated Sync Status: One Syncing, One Idle

    func testSyncStatusReportsSyncingWhenOneProviderIsSyncing() {
        let (_, _, googleSync) = injectProvider(.google, authenticated: true)
        injectProvider(.apple, authenticated: true)

        // Simulate Google syncing while Apple is idle
        googleSync.syncStatus = .syncing

        // The Combine sink triggers syncAggregatedSyncStatus asynchronously on the main actor.
        // Since we're already on @MainActor and the sink is synchronous (no async dispatch),
        // the aggregated state should be updated by the next run loop tick.
        let expectation = XCTestExpectation(description: "Sync status aggregated")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(calendarService.syncStatus, .syncing)
    }

    func testSyncStatusReturnsToIdleWhenAllProvidersIdle() {
        let (_, _, googleSync) = injectProvider(.google, authenticated: true)
        injectProvider(.apple, authenticated: true)

        googleSync.syncStatus = .syncing

        let syncExpectation = XCTestExpectation(description: "Syncing propagated")
        DispatchQueue.main.async { syncExpectation.fulfill() }
        wait(for: [syncExpectation], timeout: 2.0)

        XCTAssertEqual(calendarService.syncStatus, .syncing)

        // Return to idle
        googleSync.syncStatus = .idle

        let idleExpectation = XCTestExpectation(description: "Idle propagated")
        DispatchQueue.main.async { idleExpectation.fulfill() }
        wait(for: [idleExpectation], timeout: 2.0)

        XCTAssertEqual(calendarService.syncStatus, .idle)
    }

    // MARK: - Aggregated Sync Status: Error Propagation

    func testSyncStatusReportsErrorWhenOneProviderHasError() {
        injectProvider(.google, authenticated: true)
        let (_, _, appleSync) = injectProvider(.apple, authenticated: true)

        appleSync.syncStatus = .error("Apple Calendar sync failed")

        let expectation = XCTestExpectation(description: "Error status aggregated")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(calendarService.syncStatus, .error("Apple Calendar sync failed"))
    }

    func testSyncingTakesPriorityOverError() {
        let (_, _, googleSync) = injectProvider(.google, authenticated: true)
        let (_, _, appleSync) = injectProvider(.apple, authenticated: true)

        // Apple has error, Google is syncing — syncing should take priority
        appleSync.syncStatus = .error("Some error")
        googleSync.syncStatus = .syncing

        let expectation = XCTestExpectation(description: "Status aggregated")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(calendarService.syncStatus, .syncing)
    }

    // MARK: - Auth Error Propagation

    func testAuthErrorFromOneProviderIsExposed() {
        injectProvider(.google, authenticated: false, authError: "Token expired")
        injectProvider(.apple, authenticated: true)

        XCTAssertEqual(calendarService.authError, "Token expired")
        // Apple is still connected
        XCTAssertTrue(calendarService.isConnected)
    }

    func testUnauthenticatedProviderNotInConnectedSet() {
        injectProvider(.google, authenticated: false)
        injectProvider(.apple, authenticated: true)

        XCTAssertEqual(calendarService.connectedProviders, Set([.apple]))
        XCTAssertTrue(calendarService.isConnected)
    }
}
