@testable import Unmissable
import XCTest

/// Verifies that model types expose human-readable display properties
/// suitable for UI labels and screen reader descriptions.
@MainActor
final class DisplayPropertyTests: XCTestCase {
    // MARK: - Event Display Data

    func testEventProvidesHumanReadableProperties() {
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
            updatedAt: Date()
        )

        XCTAssertEqual(event.title, "Design Review")
        XCTAssertEqual(event.organizer, "alice@example.com")
        XCTAssertEqual(event.startDate, start)
        XCTAssertEqual(event.endDate, end)
        XCTAssertEqual(event.duration, 3600)
    }

    // Provider display names and attendee status display texts are
    // tested in ProviderTests and AttendeeModelTests respectively.
    // This file focuses on display properties NOT tested elsewhere.

    // MARK: - Sync Status

    func testSyncStatusDescriptionIsReadable() {
        XCTAssertEqual(SyncStatus.idle.description, "Ready")
        XCTAssertEqual(
            SyncStatus.syncing.description,
            "Syncing..."
        )
        XCTAssertEqual(
            SyncStatus.offline.description,
            "Offline"
        )
        XCTAssertEqual(
            SyncStatus.error("timeout").description,
            "Error: timeout"
        )
    }

    // MARK: - Health Status

    func testHealthStatusIsHealthyReturnsCorrectValues() {
        XCTAssertTrue(HealthStatus.healthy.isHealthy)

        let warning = HealthIssue(
            severity: .warning,
            component: "Sync",
            message: "Last sync was 10 minutes ago",
            suggestion: "Check network connection"
        )
        let degraded = HealthStatus.degraded(issues: [warning])
        XCTAssertFalse(degraded.isHealthy)

        let error = HealthIssue(
            severity: .error,
            component: "Database",
            message: "DB not initialized",
            suggestion: "Restart the app"
        )
        let critical = HealthStatus.critical(issues: [error])
        XCTAssertFalse(critical.isHealthy)
    }

    func testHealthStatusEquatable_healthyEqualsHealthy() {
        XCTAssertEqual(HealthStatus.healthy, HealthStatus.healthy)
    }

    func testHealthStatusEquatable_degradedWithSameIssuesAreEqual() {
        let issue = HealthIssue(
            severity: .warning,
            component: "Test",
            message: "Test issue",
            suggestion: "Fix it"
        )
        // Note: HealthIssue has UUID id, so two instances are never equal
        // even with same content. This tests that .degraded([issue]) == .degraded([issue])
        // using the SAME instance.
        let status1 = HealthStatus.degraded(issues: [issue])
        let status2 = HealthStatus.degraded(issues: [issue])
        XCTAssertEqual(status1, status2)
    }

    func testHealthStatusEquatable_healthyNotEqualToDegraded() {
        let issue = HealthIssue(
            severity: .warning,
            component: "Test",
            message: "msg",
            suggestion: "sug"
        )
        XCTAssertNotEqual(HealthStatus.healthy, HealthStatus.degraded(issues: [issue]))
    }

    func testHealthStatusEquatable_degradedNotEqualToCritical() {
        let issue = HealthIssue(
            severity: .error,
            component: "DB",
            message: "msg",
            suggestion: "sug"
        )
        XCTAssertNotEqual(
            HealthStatus.degraded(issues: [issue]),
            HealthStatus.critical(issues: [issue])
        )
    }

    func testHealthSeverityAllCases() {
        XCTAssertEqual(HealthIssue.Severity.allCases.count, 2)
        XCTAssertTrue(HealthIssue.Severity.allCases.contains(.warning))
        XCTAssertTrue(HealthIssue.Severity.allCases.contains(.error))
    }

    func testHealthSeverityRawValues() {
        XCTAssertEqual(HealthIssue.Severity.warning.rawValue, "warning")
        XCTAssertEqual(HealthIssue.Severity.error.rawValue, "error")
    }

    func testHealthIssueCarriesAccessibleContext() {
        let issue = HealthIssue(
            severity: .warning,
            component: "Calendar Service",
            message: "No calendars connected",
            suggestion: "Connect a calendar in settings"
        )

        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.component, "Calendar Service")
        XCTAssertEqual(
            issue.message,
            "No calendars connected"
        )
        XCTAssertEqual(
            issue.suggestion,
            "Connect a calendar in settings"
        )
    }
}
