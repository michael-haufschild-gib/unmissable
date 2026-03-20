@testable import Unmissable
import XCTest

@MainActor
final class HealthMonitorTests: XCTestCase {
    func testInit_performsInitialHealthCheckImmediately() async throws {
        var monitor: HealthMonitor? = HealthMonitor()

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertNotNil(monitor?.metrics.lastHealthCheck)

        monitor = nil
    }

    func testSetup_triggersImmediateHealthEvaluationWithDependencies() async throws {
        let preferences = TestUtilities.createTestPreferencesManager()
        let calendarService = CalendarService(preferencesManager: preferences)
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)
        let syncManager = SyncManager(
            apiService: apiService,
            databaseManager: DatabaseManager.shared,
            preferencesManager: preferences
        )
        let overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        let monitor = HealthMonitor()

        monitor.setup(
            calendarService: calendarService,
            syncManager: syncManager,
            overlayManager: overlayManager
        )

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            guard case let .degraded(issues) = monitor.healthStatus else { return false }
            return issues.contains(where: { $0.component == "Calendar Service" })
        }
    }

    func testSetup_afterInitialCheck_refreshesHealthWithoutWaitingFullInterval() async throws {
        let preferences = TestUtilities.createTestPreferencesManager()
        let calendarService = CalendarService(preferencesManager: preferences)
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)
        let syncManager = SyncManager(
            apiService: apiService,
            databaseManager: DatabaseManager.shared,
            preferencesManager: preferences
        )
        let overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        let monitor = HealthMonitor()

        // Let the initial check run before dependencies are attached.
        try await Task.sleep(for: .milliseconds(250))

        monitor.setup(
            calendarService: calendarService,
            syncManager: syncManager,
            overlayManager: overlayManager
        )

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            guard case let .degraded(issues) = monitor.healthStatus else { return false }
            return issues.contains(where: { $0.component == "Calendar Service" })
        }
    }
}
