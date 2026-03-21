import Foundation
@testable import Unmissable
import XCTest

/// E2E tests for the overlay trigger and interaction flow through the full stack.
/// Tests: DB event → scheduler trigger → overlay shows → snooze/dismiss/join → state consistency.
@MainActor
final class OverlayFlowE2ETests: XCTestCase {
    private var env: E2ETestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        env = try E2ETestEnvironment()
    }

    override func tearDown() async throws {
        env.tearDown()
        env = nil
        try await super.tearDown()
    }

    // MARK: - Overlay Triggered from DB Events

    func testSchedulerTriggersOverlayForImminentEvent() async throws {
        // Event starting very soon with overlayShowMinutesBefore = 0
        // This makes the scheduler show the overlay immediately
        env.preferencesManager.setOverlayShowMinutesBefore(0)

        let imminentEvent = E2EEventBuilder.futureEvent(
            id: "e2e-imminent",
            title: "Imminent Meeting",
            minutesFromNow: 1 // 1 minute from now
        )

        try await env.seedAndSchedule([imminentEvent])

        // Wait for overlay to be triggered
        try await e2eWait(timeout: 35.0, description: "Overlay should appear for imminent event") {
            self.env.overlayManager.isOverlayVisible
        }

        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, imminentEvent.id)
        XCTAssertEqual(env.overlayManager.activeEvent?.title, "Imminent Meeting")
    }

    // MARK: - Snooze Flow Through Full Stack

    func testSnoozeFlowFromOverlayThroughScheduler() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-flow",
            title: "Snooze Flow Meeting",
            minutesFromNow: 15
        )

        try await env.seedAndSchedule([event])

        // Manually show overlay (simulating scheduler trigger)
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)

        // Snooze for 3 minutes
        env.overlayManager.snoozeOverlay(for: 3)

        // Verify: overlay hidden
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)

        // Verify: snooze alert scheduled in EventScheduler
        let snoozeAlerts = env.eventScheduler.scheduledAlerts.filter { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        XCTAssertEqual(snoozeAlerts.count, 1)

        // Verify snooze is for the correct event
        let snoozeAlert = try XCTUnwrap(snoozeAlerts.first)
        XCTAssertEqual(snoozeAlert.event.id, event.id)

        // Verify snooze time is approximately correct (3 minutes from now)
        if case let .snooze(until) = snoozeAlert.alertType {
            let expectedTime = Date().addingTimeInterval(3 * 60)
            let drift = abs(until.timeIntervalSince(expectedTime))
            XCTAssertLessThan(drift, 5.0, "Snooze time should be ~3 minutes from now")
        } else {
            XCTFail("Expected snooze alert type")
        }
    }

    func testSnoozeWithDifferentDurationsSchedulesCorrectly() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-durations",
            minutesFromNow: 30
        )
        try await env.seedAndSchedule([event])

        for duration in [1, 5, 10, 15] {
            env.eventScheduler.scheduledAlerts.removeAll()

            env.overlayManager.showOverlayImmediately(for: event)
            XCTAssertTrue(env.overlayManager.isOverlayVisible)

            env.overlayManager.snoozeOverlay(for: duration)

            XCTAssertFalse(env.overlayManager.isOverlayVisible)

            // Find the snooze alert and verify its duration
            let snoozeAlert = env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType { return true }
                return false
            }
            XCTAssertNotNil(snoozeAlert, "Snooze alert should exist for \(duration) minutes")

            if case let .snooze(until) = snoozeAlert?.alertType {
                let expectedMinutes = Int(ceil(until.timeIntervalSinceNow / 60))
                XCTAssertEqual(
                    expectedMinutes, duration,
                    "Snooze should schedule for \(duration) minutes"
                )
            }
        }
    }

    // MARK: - Dismiss Flow

    func testDismissFlowDoesNotScheduleSnooze() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-dismiss-flow",
            title: "Dismiss Flow Meeting",
            minutesFromNow: 20
        )

        try await env.seedAndSchedule([event])

        // Show and dismiss
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        env.overlayManager.hideOverlay()

        // Verify: overlay hidden, no snooze
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)

        let hasSnooze = env.eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        XCTAssertFalse(hasSnooze, "Dismiss should not create a snooze alert")
    }

    // MARK: - Auto-Hide for Old Meetings

    func testOverlayAutoHidesForMeetingStartedTooLongAgo() async throws {
        // Meeting that started more than 5 minutes ago (non-snooze threshold)
        let oldEvent = E2EEventBuilder.startedEvent(
            id: "e2e-auto-hide",
            title: "Very Old Meeting",
            minutesAgo: 10 // Started 10 minutes ago
        )

        try await env.seedEvents([oldEvent])

        // Try to show overlay for this old meeting — should auto-dismiss
        env.overlayManager.showOverlayImmediately(for: oldEvent)

        XCTAssertFalse(
            env.overlayManager.isOverlayVisible,
            "Overlay should auto-hide for meetings started >5 minutes ago"
        )
    }

    func testOverlayShowsForRecentlyStartedMeeting() async throws {
        // Meeting that started just 2 minutes ago
        let recentEvent = E2EEventBuilder.startedEvent(
            id: "e2e-recent-start",
            title: "Just Started Meeting",
            minutesAgo: 2
        )

        try await env.seedEvents([recentEvent])

        env.overlayManager.showOverlayImmediately(for: recentEvent)

        XCTAssertTrue(
            env.overlayManager.isOverlayVisible,
            "Overlay should show for recently started meetings"
        )
        XCTAssertEqual(env.overlayManager.activeEvent?.id, recentEvent.id)
    }

    func testSnoozedOverlayHasLongerAutoHideThreshold() async throws {
        // Meeting started 20 minutes ago — normally would auto-hide
        // But fromSnooze allows up to 30 minutes
        let snoozedEvent = E2EEventBuilder.startedEvent(
            id: "e2e-snooze-threshold",
            title: "Snoozed Old Meeting",
            minutesAgo: 20
        )

        try await env.seedEvents([snoozedEvent])

        // Show as if from snooze
        env.overlayManager.showOverlayImmediately(for: snoozedEvent, fromSnooze: true)

        XCTAssertTrue(
            env.overlayManager.isOverlayVisible,
            "Snoozed overlay should show for meetings started up to 30 minutes ago"
        )
    }

    // MARK: - Overlay Replaces Previous Event

    func testOverlayReplacesActiveEventWhenNewOneTriggered() async throws {
        let event1 = E2EEventBuilder.futureEvent(
            id: "e2e-replace-1",
            title: "First Meeting",
            minutesFromNow: 10
        )
        let event2 = E2EEventBuilder.futureEvent(
            id: "e2e-replace-2",
            title: "Second Meeting",
            minutesFromNow: 20
        )

        try await env.seedAndSchedule([event1, event2])

        env.overlayManager.showOverlayImmediately(for: event1)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event1.id)

        // Second event overlay replaces first
        env.overlayManager.showOverlayImmediately(for: event2)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event2.id)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
    }

    // MARK: - State Consistency After Operations

    func testStateConsistencyAfterSnoozeAndDismissCycle() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-state-consistency",
            minutesFromNow: 15
        )
        try await env.seedAndSchedule([event])

        // Show → snooze → show again → dismiss
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        env.overlayManager.snoozeOverlay(for: 5)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)

        // Simulate snooze firing — show again
        env.overlayManager.showOverlayImmediately(for: event, fromSnooze: true)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)

        // Dismiss
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)
        XCTAssertEqual(env.overlayManager.timeUntilMeeting, 0)
    }

    // MARK: - Rapid Interactions Don't Corrupt State

    func testRapidShowHideDoesNotCorruptState() async throws {
        let event = E2EEventBuilder.futureEvent(id: "e2e-rapid", minutesFromNow: 10)
        try await env.seedAndSchedule([event])

        for _ in 0 ..< 20 {
            env.overlayManager.showOverlayImmediately(for: event)
            env.overlayManager.hideOverlay()
        }

        // Final state should be clean
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)
    }

    func testRapidSnoozeDoesNotAccumulateSnoozeAlerts() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-rapid-snooze",
            minutesFromNow: 15
        )
        try await env.seedAndSchedule([event])

        // Show and snooze rapidly — only the first snooze should register
        // because subsequent snoozes have no activeEvent
        env.overlayManager.showOverlayImmediately(for: event)
        env.overlayManager.snoozeOverlay(for: 1)
        env.overlayManager.snoozeOverlay(for: 2) // No-op — no active event
        env.overlayManager.snoozeOverlay(for: 3) // No-op — no active event

        // Only 1 snooze alert should exist (plus the original reminder alerts)
        let snoozeAlerts = env.eventScheduler.scheduledAlerts.filter { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        XCTAssertEqual(snoozeAlerts.count, 1)
    }

    // MARK: - Snooze While No Overlay Is No-Op

    func testSnoozeWithNoActiveOverlayIsNoOp() async throws {
        let event = E2EEventBuilder.futureEvent(id: "e2e-no-overlay-snooze", minutesFromNow: 20)
        try await env.seedAndSchedule([event])

        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        env.overlayManager.snoozeOverlay(for: 5)

        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        let hasSnooze = env.eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        XCTAssertFalse(hasSnooze, "Snooze with no active overlay should not schedule anything")
    }

    // MARK: - Online Meeting Data Preserved in Overlay

    func testOnlineMeetingDataAvailableInOverlay() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-meet-overlay",
            title: "Google Meet E2E",
            minutesFromNow: 10,
            provider: .meet
        )

        try await env.seedAndSchedule([meetEvent])

        // Fetch from DB and show overlay
        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)

        env.overlayManager.showOverlayImmediately(for: dbEvent)

        let activeEvent = try XCTUnwrap(env.overlayManager.activeEvent)
        XCTAssertTrue(activeEvent.isOnlineMeeting)
        let link = try XCTUnwrap(activeEvent.primaryLink)
        XCTAssertEqual(link.host, "meet.google.com")
        XCTAssertEqual(activeEvent.provider, .meet)
    }
}
