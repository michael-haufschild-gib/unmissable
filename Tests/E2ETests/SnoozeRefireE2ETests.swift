import Foundation
import TestSupport
@testable import Unmissable
import XCTest

/// E2E tests for the complete snooze re-fire cycle through the full stack.
/// Tests verify: overlay shows → user snoozes → snooze alert scheduled → re-fire
/// triggers overlay with fromSnooze=true → user acts again.
///
/// Note: The monitoring loop's auto-advance + MainActor creates starvation when
/// polling via e2eWait after a snooze (refreshMonitoring restarts an instant-loop).
/// These tests simulate re-fire by calling showOverlay(fromSnooze:true) after
/// verifying the snooze alert was correctly scheduled — the same code path the
/// monitoring loop's handleTriggeredAlert executes. The monitoring loop itself
/// is already tested in SchedulerTimerE2ETests.
@MainActor
final class SnoozeRefireE2ETests: XCTestCase {
    private var env: E2ETestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        env = try await E2ETestEnvironment()
    }

    override func tearDown() async throws {
        env.tearDown()
        env = nil
        try await super.tearDown()
    }

    // MARK: - Snooze → Verify Alert → Re-Fire

    func testSnoozeSchedulesAlertThenRefireShowsOverlay() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-refire-cycle",
            title: "Refire Cycle Meeting",
            minutesFromNow: 15,
            durationMinutes: 60,
        )

        try await env.seedAndSchedule([event])

        // Show overlay (as scheduler would)
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)

        // User snoozes for 3 minutes
        env.overlayManager.snoozeOverlay(for: 3)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)

        // Verify snooze alert was correctly scheduled
        let snoozeAlert = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType, alert.event.id == event.id { return true }
                return false
            },
            "Snooze alert should be scheduled",
        )
        XCTAssertEqual(snoozeAlert.event.id, event.id)

        // Verify snooze timing is correct (~3 minutes from now)
        if case let .snooze(until) = snoozeAlert.alertType {
            let drift = abs(until.timeIntervalSince(env.testClock.currentTime) - 3 * 60)
            XCTAssertLessThan(drift, 5.0, "Snooze should fire ~3 minutes from now")
        }

        // Simulate monitoring loop firing the snooze alert
        // (same code path as handleTriggeredAlert for .snooze case)
        env.overlayManager.showOverlayImmediately(for: snoozeAlert.event, fromSnooze: true)

        XCTAssertTrue(env.overlayManager.isOverlayVisible, "Overlay should re-appear from snooze")
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)
    }

    // MARK: - Double Snooze Cycle

    func testDoubleSnoozeRefire() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-double-refire",
            title: "Double Snooze Meeting",
            minutesFromNow: 15,
            durationMinutes: 60,
        )
        try await env.seedAndSchedule([event])

        // First cycle: show → snooze → verify alert → re-fire
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)

        env.overlayManager.snoozeOverlay(for: 1)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        let firstSnooze = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType { return true }
                return false
            },
        )
        XCTAssertEqual(firstSnooze.event.id, event.id)

        // Re-fire from first snooze
        env.overlayManager.showOverlayImmediately(for: event, fromSnooze: true)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        // Second cycle: snooze again → verify new alert → re-fire again
        env.overlayManager.snoozeOverlay(for: 5)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Find all snooze alerts for this event — should be 2 (1 min and 5 min)
        let snoozeAlerts = env.eventScheduler.scheduledAlerts.filter { alert in
            if case .snooze = alert.alertType, alert.event.id == event.id { return true }
            return false
        }
        // Verify both snoozes: first at ~1 min, second at ~5 min from test clock
        let firstSnoozeAlert = try XCTUnwrap(snoozeAlerts.first)
        let latestSnooze = try XCTUnwrap(snoozeAlerts.last)
        XCTAssertNotEqual(firstSnoozeAlert.id, latestSnooze.id, "Should have two distinct snooze alerts")
        if case let .snooze(until) = latestSnooze.alertType {
            let drift = abs(until.timeIntervalSince(env.testClock.currentTime) - 5 * 60)
            XCTAssertLessThan(drift, 5.0, "Latest snooze should fire ~5 minutes from now")
        }

        // Re-fire from second snooze
        env.overlayManager.showOverlayImmediately(for: event, fromSnooze: true)
        XCTAssertTrue(env.overlayManager.isOverlayVisible, "Overlay re-appears after second snooze")
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)
    }

    // MARK: - Snooze Re-Fire After Meeting Started

    func testSnoozeRefireWorksAfterMeetingHasStarted() async throws {
        // Meeting started 2 min ago — overlay shows for recently started meeting
        let startedEvent = E2EEventBuilder.startedEvent(
            id: "e2e-refire-started",
            title: "Refire After Start",
            minutesAgo: 2,
            durationMinutes: 60,
        )
        try await env.seedEvents([startedEvent])

        // Show overlay for recently started meeting (within 5-min normal threshold)
        env.overlayManager.showOverlayImmediately(for: startedEvent)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        // Snooze for 5 minutes — by re-fire time, meeting will be 7 min old
        // (beyond normal 5-min threshold, but within 30-min snooze threshold)
        env.overlayManager.snoozeOverlay(for: 5)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        let snoozeAlert = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType { return true }
                return false
            },
        )

        // Simulate re-fire with fromSnooze=true (30-min threshold applies)
        env.overlayManager.showOverlayImmediately(for: snoozeAlert.event, fromSnooze: true)

        XCTAssertTrue(
            env.overlayManager.isOverlayVisible,
            "Snoozed overlay should re-appear even after meeting started (30-min threshold)",
        )
        XCTAssertEqual(env.overlayManager.activeEvent?.id, startedEvent.id)
    }

    // MARK: - Snooze Re-Fire Preserves Event Data

    func testSnoozeRefirePreservesFullEventData() async throws {
        let event = E2EEventBuilder.onlineMeeting(
            id: "e2e-refire-data",
            title: "Data Preservation Meeting",
            minutesFromNow: 15,
            provider: .zoom,
        )
        try await env.seedAndSchedule([event])

        // Fetch from DB to get round-tripped event
        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)

        // Show → snooze → verify alert preserves data → re-fire
        env.overlayManager.showOverlayImmediately(for: dbEvent)
        env.overlayManager.snoozeOverlay(for: 1)

        let snoozeAlert = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType { return true }
                return false
            },
        )

        // The snooze alert's event should preserve all data from DB round-trip
        let snoozeEvent = snoozeAlert.event
        XCTAssertEqual(snoozeEvent.id, event.id)
        XCTAssertEqual(snoozeEvent.title, "Data Preservation Meeting")
        XCTAssertEqual(snoozeEvent.provider, .zoom)
        XCTAssertTrue(LinkParser().isOnlineMeeting(snoozeEvent))

        let link = try XCTUnwrap(LinkParser().primaryLink(for: snoozeEvent))
        XCTAssertEqual(link.host, "zoom.us")

        // Re-fire shows correct data
        env.overlayManager.showOverlayImmediately(for: snoozeEvent, fromSnooze: true)
        let activeEvent = try XCTUnwrap(env.overlayManager.activeEvent)
        XCTAssertEqual(activeEvent.title, "Data Preservation Meeting")
        XCTAssertEqual(activeEvent.provider, .zoom)
    }

    // MARK: - Snooze Re-Fire Then Dismiss Ends Flow

    func testSnoozeRefireThenDismissEndsFlow() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-refire-dismiss",
            title: "Refire Then Dismiss",
            minutesFromNow: 20,
            durationMinutes: 60,
        )
        try await env.seedAndSchedule([event])

        // Show → snooze → re-fire → dismiss
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        env.overlayManager.snoozeOverlay(for: 1)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Re-fire
        env.overlayManager.showOverlayImmediately(for: event, fromSnooze: true)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        // User dismisses
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)
        XCTAssertEqual(env.overlayManager.timeUntilMeeting, 0)
    }

    // MARK: - Snooze Preserved During Rescheduling

    func testSnoozeAlertSurvivesRescheduling() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-refire-reschedule",
            title: "Survive Reschedule",
            minutesFromNow: 20,
            durationMinutes: 60,
        )
        try await env.seedAndSchedule([event])

        // Show and snooze
        env.overlayManager.showOverlayImmediately(for: event)
        env.overlayManager.snoozeOverlay(for: 5)

        // Verify snooze exists
        let initialSnoozeCount = env.eventScheduler.scheduledAlerts.count(where: { alert in
            if case .snooze = alert.alertType { return true }
            return false
        })
        XCTAssertEqual(initialSnoozeCount, 1)

        // Trigger rescheduling by changing a preference
        env.preferencesManager.setOverlayShowMinutesBefore(8)

        // Give Combine observer time to fire
        await Task.yield()

        // Snooze alert should survive the rescheduling
        let postRescheduleSnoozes = env.eventScheduler.scheduledAlerts.filter { alert in
            if case .snooze = alert.alertType, alert.event.id == event.id { return true }
            return false
        }
        let survivedSnooze = try XCTUnwrap(
            postRescheduleSnoozes.first,
            "Snooze alert should survive rescheduling",
        )
        XCTAssertEqual(
            postRescheduleSnoozes.map(\.event.id),
            [event.id],
            "Exactly one snooze alert should survive rescheduling",
        )
        // Verify the rescheduling actually produced new non-snooze alerts
        let reminderAlerts = env.eventScheduler.scheduledAlerts.filter { alert in
            if case .reminder = alert.alertType { return true }
            return false
        }
        XCTAssertFalse(reminderAlerts.isEmpty, "Rescheduling should produce at least one reminder alert")
    }

    // MARK: - Multiple Events With Interleaved Snooze

    func testInterleavedSnoozeForMultipleEvents() async throws {
        let event1 = E2EEventBuilder.futureEvent(
            id: "e2e-interleave-1",
            title: "Interleave Meeting 1",
            minutesFromNow: 10,
            durationMinutes: 60,
        )
        let event2 = E2EEventBuilder.futureEvent(
            id: "e2e-interleave-2",
            title: "Interleave Meeting 2",
            minutesFromNow: 15,
            durationMinutes: 60,
        )
        try await env.seedAndSchedule([event1, event2])

        // Show event 1 → snooze
        env.overlayManager.showOverlayImmediately(for: event1)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event1.id)

        env.overlayManager.snoozeOverlay(for: 5)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Event 2 triggers while event 1 is snoozed
        env.overlayManager.showOverlayImmediately(for: event2)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event2.id)

        // Dismiss event 2
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Event 1 snooze re-fires
        let snoozeAlert = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType, alert.event.id == event1.id { return true }
                return false
            },
        )
        env.overlayManager.showOverlayImmediately(for: snoozeAlert.event, fromSnooze: true)

        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(
            env.overlayManager.activeEvent?.id,
            event1.id,
            "Snoozed event 1 should re-fire after event 2 dismissed",
        )
    }

    // MARK: - Snooze As Only Alert

    func testSnoozeIsOnlyAlertAfterAllRemindersConsumed() async throws {
        env.preferencesManager.setPlayAlertSound(false)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-sole-snooze",
            title: "Sole Snooze Meeting",
            minutesFromNow: 15,
            durationMinutes: 60,
        )
        try await env.seedAndSchedule([event])

        // Show overlay (consuming the reminder alert scenario)
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        // Snooze — creates the only remaining alert
        env.overlayManager.snoozeOverlay(for: 1)

        let alerts = env.eventScheduler.scheduledAlerts
        let snoozeAlerts = alerts.filter { if case .snooze = $0.alertType { return true }
            return false
        }
        let soloSnooze = try XCTUnwrap(snoozeAlerts.first, "Should have exactly one snooze alert")
        XCTAssertEqual(snoozeAlerts.map(\.event.id), [event.id], "Only snooze for this event")
        XCTAssertEqual(soloSnooze.event.id, event.id)

        // Re-fire works when snooze is the only alert
        env.overlayManager.showOverlayImmediately(for: soloSnooze.event, fromSnooze: true)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)
    }
}
