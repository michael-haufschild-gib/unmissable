import Foundation
import Testing
@testable import Unmissable

@MainActor
struct HealthMonitorTests {
    @Test
    func init_performsInitialHealthCheckImmediately() async throws {
        var monitor: HealthMonitor? = HealthMonitor()

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            monitor?.metrics.lastHealthCheck != nil
        }

        let lastCheck = try #require(monitor?.metrics.lastHealthCheck)
        #expect(lastCheck > Date.distantPast)

        monitor = nil
    }

    @Test
    func setup_triggersImmediateHealthEvaluationWithDependencies() async throws {
        let preferences = TestUtilities.createTestPreferencesManager()
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-test-\(UUID().uuidString).db")
        let calendarService = CalendarService(
            preferencesManager: preferences,
            databaseManager: DatabaseManager(databaseURL: dbURL),
            linkParser: LinkParser(),
        )
        let overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        let monitor = HealthMonitor()

        monitor.setup(
            calendarService: calendarService,
            overlayManager: overlayManager,
        )

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            guard case let .degraded(issues) = monitor.healthStatus else { return false }
            return issues.contains(where: { $0.component == "Calendar Service" })
        }
    }

    @Test
    func setup_afterInitialCheck_refreshesHealthWithoutWaitingFullInterval() async throws {
        let preferences = TestUtilities.createTestPreferencesManager()
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-test-\(UUID().uuidString).db")
        let calendarService = CalendarService(
            preferencesManager: preferences,
            databaseManager: DatabaseManager(databaseURL: dbURL),
            linkParser: LinkParser(),
        )
        let overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        let monitor = HealthMonitor()

        // Let the initial check run before dependencies are attached.
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            monitor.metrics.lastHealthCheck != nil
        }

        monitor.setup(
            calendarService: calendarService,
            overlayManager: overlayManager,
        )

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            guard case let .degraded(issues) = monitor.healthStatus else { return false }
            return issues.contains(where: { $0.component == "Calendar Service" })
        }
    }

    // MARK: - HealthIssue Equality

    @Test
    func healthIssue_equalityIgnoresId() {
        let a = HealthIssue(severity: .error, component: "Sync", message: "Timeout", suggestion: "Retry")
        let b = HealthIssue(severity: .error, component: "Sync", message: "Timeout", suggestion: "Retry")

        // Different UUID instances but identical content — should be equal
        #expect(a == b, "HealthIssues with identical content should be equal regardless of id")
    }

    @Test
    func healthIssue_inequalityOnDifferentContent() {
        let a = HealthIssue(severity: .error, component: "Sync", message: "Timeout", suggestion: "Retry")
        let b = HealthIssue(severity: .warning, component: "Sync", message: "Timeout", suggestion: "Retry")

        #expect(a != b, "HealthIssues with different severity should not be equal")
    }
}
