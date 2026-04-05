import Foundation
import Testing
@testable import Unmissable

/// Verifies that model types expose human-readable display properties
/// suitable for UI labels and screen reader descriptions.
@MainActor
struct DisplayPropertyTests {
    // MARK: - Event Display Data

    @Test
    func eventProvidesHumanReadableProperties() {
        let start = Date()
        let end = start.addingTimeInterval(3600)

        let event = Event(
            id: "a11y-event",
            title: "Design Review",
            startDate: start,
            endDate: end,
            organizer: "alice@example.com",
            calendarId: "primary",
            timezone: "America/Chicago",
            createdAt: Date(),
            updatedAt: Date(),
        )

        #expect(event.title == "Design Review")
        #expect(event.organizer == "alice@example.com")
        #expect(event.startDate == start)
        #expect(event.endDate == end)
        #expect(event.duration == 3600)
    }

    // Provider display names and attendee status display texts are
    // tested in ProviderTests and AttendeeModelTests respectively.
    // This file focuses on display properties NOT tested elsewhere.

    // MARK: - Sync Status

    @Test
    func syncStatusDescriptionIsReadable() {
        #expect(SyncStatus.idle.description == "Ready")
        #expect(
            SyncStatus.syncing.description == "Syncing...",
        )
        #expect(
            SyncStatus.offline.description == "Offline",
        )
        #expect(
            SyncStatus.error("timeout").description == "Error: timeout",
        )
    }

    // MARK: - Health Status

    @Test
    func healthStatusIsHealthyReturnsCorrectValues() {
        #expect(HealthStatus.healthy.isHealthy)

        let warning = HealthIssue(
            severity: .warning,
            component: "Sync",
            message: "Last sync was 10 minutes ago",
            suggestion: "Check network connection",
        )
        let degraded = HealthStatus.degraded(issues: [warning])
        #expect(!degraded.isHealthy)

        let error = HealthIssue(
            severity: .error,
            component: "Database",
            message: "DB not initialized",
            suggestion: "Restart the app",
        )
        let critical = HealthStatus.critical(issues: [error])
        #expect(!critical.isHealthy)
    }

    @Test
    func healthStatusEquatable_healthyEqualsHealthy() {
        let status = HealthStatus.healthy
        #expect(status == .healthy)
    }

    @Test
    func healthStatusEquatable_degradedWithSameIssuesAreEqual() {
        let issue = HealthIssue(
            severity: .warning,
            component: "Test",
            message: "Test issue",
            suggestion: "Fix it",
        )
        // Note: HealthIssue has UUID id, so two instances are never equal
        // even with same content. This tests that .degraded([issue]) == .degraded([issue])
        // using the SAME instance.
        let status1 = HealthStatus.degraded(issues: [issue])
        let status2 = HealthStatus.degraded(issues: [issue])
        #expect(status1 == status2)
    }

    @Test
    func healthStatusEquatable_healthyNotEqualToDegraded() {
        let issue = HealthIssue(
            severity: .warning,
            component: "Test",
            message: "msg",
            suggestion: "sug",
        )
        #expect(HealthStatus.healthy != HealthStatus.degraded(issues: [issue]))
    }

    @Test
    func healthStatusEquatable_degradedNotEqualToCritical() {
        let issue = HealthIssue(
            severity: .error,
            component: "DB",
            message: "msg",
            suggestion: "sug",
        )
        #expect(
            HealthStatus.degraded(issues: [issue]) != HealthStatus.critical(issues: [issue]),
        )
    }

    @Test
    func healthSeverityAllCases() {
        #expect(
            HealthIssue.Severity.allCases == [.warning, .error],
            "Severity allCases should contain exactly warning and error",
        )
    }

    @Test
    func healthSeverityRawValues() {
        #expect(HealthIssue.Severity.warning.rawValue == "warning")
        #expect(HealthIssue.Severity.error.rawValue == "error")
    }

    @Test
    func healthIssueCarriesAccessibleContext() {
        let issue = HealthIssue(
            severity: .warning,
            component: "Calendar Service",
            message: "No calendars connected",
            suggestion: "Connect a calendar in settings",
        )

        #expect(issue.severity == .warning)
        #expect(issue.component == "Calendar Service")
        #expect(
            issue.message == "No calendars connected",
        )
        #expect(
            issue.suggestion == "Connect a calendar in settings",
        )
    }
}
