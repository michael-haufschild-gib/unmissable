import Foundation
import Testing
@testable import Unmissable

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

    // swiftlint:disable:next async_without_await
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
    /// Per-calendar results returned by `fetchEvents`. When nil, auto-generates
    /// `.success` results by grouping `events` by calendarId.
    var fetchResults: CalendarFetchResults?

    // swiftlint:disable:next async_without_await
    func fetchCalendars() async -> [CalendarInfo] {
        calendars
    }

    // swiftlint:disable:next async_without_await
    func fetchEvents(for calendarIds: [String], from _: Date, to _: Date) async -> CalendarFetchResults {
        if let fetchResults {
            return fetchResults
        }
        // Auto-generate results from the flat events array for backward compatibility
        let eventsByCalendar = Dictionary(grouping: events) { $0.calendarId }
        var results: CalendarFetchResults = [:]
        for calendarId in calendarIds {
            results[calendarId] = .success(eventsByCalendar[calendarId] ?? [])
        }
        return results
    }
}

// MARK: - Multi-Provider Integration Tests

@MainActor
struct MultiProviderIntegrationTests {
    private let calendarService: CalendarService
    private let preferencesManager: PreferencesManager
    private let databaseManager: DatabaseManager

    init() {
        let tempDir = FileManager.default.temporaryDirectory
        let tempDatabaseURL = tempDir.appendingPathComponent(
            "unmissable-multiprovider-\(UUID().uuidString).db",
        )
        databaseManager = DatabaseManager(databaseURL: tempDatabaseURL)
        preferencesManager = PreferencesManager(themeManager: ThemeManager())
        calendarService = CalendarService(
            preferencesManager: preferencesManager,
            databaseManager: databaseManager,
            linkParser: LinkParser(),
        )
    }

    // MARK: - Helpers

    /// Creates and injects a mock backend for a given provider type, returning the mock auth/API
    /// so the test can manipulate state after injection.
    @discardableResult
    private func injectProvider(
        _ type: CalendarProviderType,
        authenticated: Bool = true,
        email: String? = nil,
        authError: String? = nil,
    ) -> (auth: MockCalendarAuthProvider, api: MockCalendarAPIProvider, sync: SyncManager) {
        let auth = MockCalendarAuthProvider()
        auth.isAuthenticated = authenticated
        auth.userEmail = email
        auth.authorizationError = authError

        let api = MockCalendarAPIProvider()

        let sync = SyncManager(
            providerType: type,
            apiService: api,
            databaseManager: databaseManager,
            preferencesManager: preferencesManager,
        )

        calendarService.injectTestBackend(type: type, auth: auth, api: api, sync: sync)
        return (auth, api, sync)
    }

    // MARK: - Two Providers Connected

    @Test
    func connectingTwoProvidersReportsBothInConnectedProviders() {
        injectProvider(.google, authenticated: true, email: "user@gmail.com")
        injectProvider(.apple, authenticated: true)

        #expect(calendarService.connectedProviders == Set([.google, .apple]))
        #expect(calendarService.isConnected)
        #expect(calendarService.userEmail == "user@gmail.com")
    }

    // MARK: - Disconnect One Provider

    @Test
    func disconnectingOneProviderLeavesOtherConnected() {
        injectProvider(.google, authenticated: true, email: "user@gmail.com")
        injectProvider(.apple, authenticated: true)

        #expect(calendarService.connectedProviders == Set([.google, .apple]))

        calendarService.removeTestBackend(type: .google)

        #expect(calendarService.connectedProviders == Set([.apple]))
        #expect(calendarService.isConnected)
        #expect(calendarService.userEmail == nil, "Email should clear when Google is disconnected")
    }

    @Test
    func disconnectingBothProvidersReportsDisconnected() {
        injectProvider(.google, authenticated: true)
        injectProvider(.apple, authenticated: true)

        calendarService.removeTestBackend(type: .google)
        calendarService.removeTestBackend(type: .apple)

        #expect(calendarService.connectedProviders == Set<CalendarProviderType>())
        #expect(!calendarService.isConnected)
    }

    // MARK: - Observation Yield

    // swiftlint:disable no_raw_task_sleep_in_tests - observation yield infrastructure
    private func yieldToObservation() async {
        try? await Task.sleep(for: .milliseconds(10))
    }

    // swiftlint:enable no_raw_task_sleep_in_tests

    // MARK: - Aggregated Sync Status: One Syncing, One Idle

    @Test
    func syncStatusReportsSyncingWhenOneProviderIsSyncing() async {
        let (_, _, googleSync) = injectProvider(.google, authenticated: true)
        injectProvider(.apple, authenticated: true)

        googleSync.syncStatus = .syncing
        await yieldToObservation()

        #expect(calendarService.syncStatus == .syncing)
    }

    @Test
    func syncStatusReturnsToIdleWhenAllProvidersIdle() async {
        let (_, _, googleSync) = injectProvider(.google, authenticated: true)
        injectProvider(.apple, authenticated: true)

        googleSync.syncStatus = .syncing
        await yieldToObservation()
        #expect(calendarService.syncStatus == .syncing)

        googleSync.syncStatus = .idle
        await yieldToObservation()
        #expect(calendarService.syncStatus == .idle)
    }

    // MARK: - Aggregated Sync Status: Error Propagation

    @Test
    func syncStatusReportsErrorWhenOneProviderHasError() async {
        injectProvider(.google, authenticated: true)
        let (_, _, appleSync) = injectProvider(.apple, authenticated: true)

        appleSync.syncStatus = .error("Apple Calendar sync failed")
        await yieldToObservation()

        #expect(calendarService.syncStatus == .error("Apple Calendar sync failed"))
    }

    @Test
    func syncingTakesPriorityOverError() async {
        let (_, _, googleSync) = injectProvider(.google, authenticated: true)
        let (_, _, appleSync) = injectProvider(.apple, authenticated: true)

        appleSync.syncStatus = .error("Some error")
        await yieldToObservation()
        googleSync.syncStatus = .syncing
        await yieldToObservation()

        #expect(calendarService.syncStatus == .syncing)
    }

    // MARK: - Auth Error Propagation

    @Test
    func authErrorFromOneProviderIsExposed() {
        injectProvider(.google, authenticated: false, authError: "Token expired")
        injectProvider(.apple, authenticated: true)

        #expect(calendarService.authError == "Token expired")
        // Apple is still connected
        #expect(calendarService.isConnected)
    }

    // MARK: - Reconnect After Disconnect

    @Test
    func reconnectingSameProviderRestoresState() {
        injectProvider(.google, authenticated: true, email: "user@gmail.com")
        #expect(calendarService.connectedProviders == Set([.google]))

        calendarService.removeTestBackend(type: .google)
        #expect(calendarService.connectedProviders == Set<CalendarProviderType>())

        // Reconnect
        injectProvider(.google, authenticated: true, email: "user@gmail.com")
        #expect(calendarService.connectedProviders == Set([.google]))
        #expect(calendarService.userEmail == "user@gmail.com")
    }

    // MARK: - Sync Status Transitions

    @Test
    func bothProvidersSyncingReportsSync() async {
        let (_, _, googleSync) = injectProvider(.google, authenticated: true)
        let (_, _, appleSync) = injectProvider(.apple, authenticated: true)

        googleSync.syncStatus = .syncing
        appleSync.syncStatus = .syncing
        await yieldToObservation()

        #expect(calendarService.syncStatus == .syncing)
    }

    @Test
    func oneProviderSyncingOneErrorReportsSyncing() async {
        let (_, _, googleSync) = injectProvider(.google, authenticated: true)
        let (_, _, appleSync) = injectProvider(.apple, authenticated: true)

        googleSync.syncStatus = .syncing
        await yieldToObservation()
        appleSync.syncStatus = .error("Apple error")
        await yieldToObservation()

        #expect(
            calendarService.syncStatus == .syncing,
            "Syncing should take priority over error",
        )
    }

    @Test
    func bothProvidersErrorReportsError() async {
        let (_, _, googleSync) = injectProvider(.google, authenticated: true)
        let (_, _, appleSync) = injectProvider(.apple, authenticated: true)

        googleSync.syncStatus = .error("Google error")
        appleSync.syncStatus = .error("Apple error")
        await yieldToObservation()

        // Should report one of the errors
        guard case .error = calendarService.syncStatus else {
            Issue.record("Expected error status when both providers have errors")
            return
        }
    }

    // MARK: - Edge Cases

    @Test
    func providerWithNilEmailIsNil() {
        injectProvider(.google, authenticated: true, email: nil)
        #expect(calendarService.userEmail == nil)
        #expect(calendarService.isConnected)
    }

    @Test
    func unauthenticatedProviderNotInConnectedSet() {
        injectProvider(.google, authenticated: false)
        injectProvider(.apple, authenticated: true)

        #expect(calendarService.connectedProviders == Set([.apple]))
        #expect(calendarService.isConnected)
    }
}
