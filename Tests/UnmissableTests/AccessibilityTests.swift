@testable import Unmissable
import XCTest

@MainActor
final class AccessibilityTests: XCTestCase {
    // MARK: - Event Accessibility Data

    func testEventProvidesDataForAccessibilityLabels() {
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

    // MARK: - Provider Display Names

    func testProviderDisplayNameIsHumanReadable() {
        XCTAssertEqual(Provider.meet.displayName, "Google Meet")
        XCTAssertEqual(Provider.zoom.displayName, "Zoom")
        XCTAssertEqual(
            Provider.teams.displayName,
            "Microsoft Teams"
        )
        XCTAssertEqual(
            Provider.webex.displayName,
            "Cisco Webex"
        )
        XCTAssertEqual(Provider.generic.displayName, "Other")
    }

    func testProviderIconNameIsValidSFSymbol() {
        XCTAssertEqual(Provider.meet.iconName, "video.fill")
        XCTAssertEqual(Provider.zoom.iconName, "video.fill")
        XCTAssertEqual(Provider.teams.iconName, "video.fill")
        XCTAssertEqual(Provider.webex.iconName, "video.fill")
        XCTAssertEqual(Provider.generic.iconName, "link")
    }

    // MARK: - Attendee Status

    func testAttendeeStatusDisplayTextForScreenReaders() {
        XCTAssertEqual(
            AttendeeStatus.needsAction.displayText,
            "Not responded"
        )
        XCTAssertEqual(
            AttendeeStatus.declined.displayText,
            "Declined"
        )
        XCTAssertEqual(
            AttendeeStatus.tentative.displayText,
            "Maybe"
        )
        XCTAssertEqual(
            AttendeeStatus.accepted.displayText,
            "Accepted"
        )
    }

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
