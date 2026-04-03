import TestSupport
@testable import Unmissable
import XCTest

/// Tests snooze timer expiring after meeting has started.
/// Verifies snoozed overlays appear even when the meeting has already started.
@MainActor
final class SnoozeAfterMeetingStartTest: XCTestCase {
    func testSnoozeTimerExpiresAfterMeetingStarted() async throws {
        let preferencesManager = PreferencesManager(themeManager: ThemeManager())
        let overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        let eventScheduler = EventScheduler(preferencesManager: preferencesManager, linkParser: LinkParser())
        overlayManager.setEventScheduler(eventScheduler)

        let meetingStartTime = Date().addingTimeInterval(2)
        let testEvent = TestUtilities.createTestEvent(
            id: "snooze-after-start-test",
            title: "Snooze After Start Test Meeting",
            startDate: meetingStartTime,
        )

        // Show initial overlay
        overlayManager.showOverlayImmediately(for: testEvent, fromSnooze: false)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Initial overlay should be visible")

        // Snooze for 5 minutes
        overlayManager.snoozeOverlay(for: 5)
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")

        // Wait for meeting to start
        try await TestUtilities.waitForAsync(timeout: 4.0) { @MainActor @Sendable in
            testEvent.startDate < Date()
        }

        let meetingHasStarted = testEvent.startDate < Date()
        XCTAssertTrue(meetingHasStarted, "Meeting should have started by now")

        // Show overlay from snooze after meeting started
        overlayManager.showOverlay(for: testEvent, fromSnooze: true)

        XCTAssertTrue(
            overlayManager.isOverlayVisible,
            "Snoozed overlay should be visible even after meeting started",
        )
        let activeEvent = try XCTUnwrap(overlayManager.activeEvent)
        XCTAssertEqual(activeEvent.id, testEvent.id, "Should show correct event")

        // Verify overlay stays visible for snoozed alerts
        try await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            overlayManager.isOverlayVisible
        }

        XCTAssertTrue(
            overlayManager.isOverlayVisible,
            "Snoozed overlay should remain visible longer than regular overlays",
        )

        overlayManager.hideOverlay()
        eventScheduler.stopScheduling()
    }

    func testSnoozeAutoHideThresholds() async throws {
        let overlayManager = TestSafeOverlayManager(isTestEnvironment: true)

        let meetingStartTime = Date().addingTimeInterval(-600) // 10 minutes ago
        let testEvent = TestUtilities.createTestEvent(
            id: "auto-hide-threshold-test",
            title: "Auto-Hide Threshold Test",
            startDate: meetingStartTime,
        )

        // Regular overlay should auto-hide quickly (5 minute threshold)
        overlayManager.showOverlayImmediately(for: testEvent, fromSnooze: false)

        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            !overlayManager.isOverlayVisible
        }

        XCTAssertFalse(
            overlayManager.isOverlayVisible,
            "Regular overlay should auto-hide for meetings that started >5 minutes ago",
        )

        // Snoozed overlay should be more lenient (30 minute threshold)
        overlayManager.showOverlay(for: testEvent, fromSnooze: true)

        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            overlayManager.isOverlayVisible
        }

        XCTAssertTrue(
            overlayManager.isOverlayVisible,
            "Snoozed overlay should remain visible for meetings that started <30 minutes ago",
        )

        overlayManager.hideOverlay()
    }

    func testSnoozeLoggingAndDebugInfo() {
        let preferencesManager = PreferencesManager(themeManager: ThemeManager())
        let overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        let eventScheduler = EventScheduler(preferencesManager: preferencesManager, linkParser: LinkParser())
        overlayManager.setEventScheduler(eventScheduler)

        let testEvent = TestUtilities.createTestEvent(
            id: "snooze-logging-test",
            title: "Snooze Logging Test",
            startDate: Date().addingTimeInterval(300),
        )

        eventScheduler.scheduleSnooze(for: testEvent, minutes: 1)

        XCTAssertTrue(
            eventScheduler.scheduledAlerts.contains { alert in
                if case .snooze = alert.alertType {
                    return alert.event.id == testEvent.id
                }
                return false
            }, "Snooze alert should be scheduled",
        )

        overlayManager.showOverlayImmediately(for: testEvent, fromSnooze: true)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Snoozed overlay should be visible")

        overlayManager.hideOverlay()
        eventScheduler.stopScheduling()
    }

    func testOverlayMessagingForSnoozedMeetings() {
        // Verify OverlayContentView can be constructed for each snoozed meeting state
        let futureView = OverlayContentView(
            event: TestUtilities.createTestEvent(
                id: "snooze-future-test",
                title: "Future Snoozed Meeting",
                startDate: Date().addingTimeInterval(300),
            ),
            linkParser: LinkParser(),
            onDismiss: {},
            onJoin: {},
            onSnooze: { _ in },
            isFromSnooze: true,
        )

        let recentView = OverlayContentView(
            event: TestUtilities.createTestEvent(
                id: "snooze-recent-test",
                title: "Recently Started Snoozed Meeting",
                startDate: Date().addingTimeInterval(-120),
            ),
            linkParser: LinkParser(),
            onDismiss: {},
            onJoin: {},
            onSnooze: { _ in },
            isFromSnooze: true,
        )

        let ongoingView = OverlayContentView(
            event: TestUtilities.createTestEvent(
                id: "snooze-ongoing-test",
                title: "Long Running Snoozed Meeting",
                startDate: Date().addingTimeInterval(-900),
            ),
            linkParser: LinkParser(),
            onDismiss: {},
            onJoin: {},
            onSnooze: { _ in },
            isFromSnooze: true,
        )

        // Verify all views constructed without issues by checking a meaningful property
        XCTAssertEqual(futureView.event.id, "snooze-future-test")
        XCTAssertEqual(recentView.event.id, "snooze-recent-test")
        XCTAssertEqual(ongoingView.event.id, "snooze-ongoing-test")
    }
}
