import Foundation
import TestSupport
@testable import Unmissable
import XCTest

/// E2E tests for complete multi-step user journeys from start to finish.
/// Each test chains 3+ sequential user actions through the full stack:
/// DB → scheduler → overlay → user action → state change → next step.
/// These are the CTO's core ask: "every user interaction flow, not just one action."
///
/// Note: Tests that snooze use manual re-fire (showOverlayImmediately fromSnooze:true)
/// rather than e2eWait after snooze, because refreshMonitoring + TestClock autoAdvance
/// creates an infinite tight loop on MainActor that starves the e2eWait poller.
/// The monitoring loop itself is tested separately in SchedulerTimerE2ETests.
@MainActor
final class UserJourneyE2ETests: XCTestCase {
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

    // MARK: - Full Journey: Event → Overlay → Snooze → Re-Fire → Dismiss

    func testFullJourney_eventToSnoozeToRefireToDismiss() async throws {
        // Step 1: Event arrives in DB with meeting link
        let event = E2EEventBuilder.onlineMeeting(
            id: "e2e-journey-1",
            title: "Journey Meeting",
            minutesFromNow: 15,
            provider: .meet,
        )
        try await env.seedAndSchedule([event])

        // Fetch from DB — verify round-trip
        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)
        XCTAssertEqual(dbEvent.id, event.id)

        // Step 2: Overlay shows (simulating scheduler trigger)
        env.overlayManager.showOverlayImmediately(for: dbEvent)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)
        XCTAssertTrue(LinkParser().isOnlineMeeting(dbEvent))

        // Step 3: User snoozes
        env.overlayManager.snoozeOverlay(for: 3)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)

        // Verify snooze alert scheduled
        let snoozeAlert = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType { return true }
                return false
            },
        )
        XCTAssertEqual(snoozeAlert.event.id, event.id)

        // Step 4: Snooze re-fires
        env.overlayManager.showOverlayImmediately(for: snoozeAlert.event, fromSnooze: true)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)

        // Step 5: User dismisses
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)
        XCTAssertEqual(env.overlayManager.timeUntilMeeting, 0)
    }

    // MARK: - Full Journey: Three Events Sequential Flow

    func testFullJourney_threeEventsSequentialDismissSnoozeFlow() async throws {
        let events = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-seq-journey-\(i)",
                title: "Sequential Journey \(i + 1)",
                minutesFromNow: 10 + (i * 10),
                durationMinutes: 30,
            )
        }
        try await env.seedAndSchedule(events)

        // Event 0: overlay → user dismisses
        env.overlayManager.showOverlayImmediately(for: events[0])
        XCTAssertEqual(env.overlayManager.activeEvent?.title, "Sequential Journey 1")
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Event 1: overlay → user snoozes
        env.overlayManager.showOverlayImmediately(for: events[1])
        XCTAssertEqual(env.overlayManager.activeEvent?.title, "Sequential Journey 2")
        env.overlayManager.snoozeOverlay(for: 5)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Event 2: overlay → user dismisses
        env.overlayManager.showOverlayImmediately(for: events[2])
        XCTAssertEqual(env.overlayManager.activeEvent?.title, "Sequential Journey 3")
        env.overlayManager.hideOverlay()

        // Event 1 snooze re-fires
        let snoozeAlert = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType, alert.event.id == events[1].id { return true }
                return false
            },
        )
        env.overlayManager.showOverlayImmediately(for: snoozeAlert.event, fromSnooze: true)
        XCTAssertEqual(env.overlayManager.activeEvent?.title, "Sequential Journey 2")

        // User finally dismisses
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)
    }

    // MARK: - Full Journey: Sync Update → Reschedule → Correct Overlay

    func testFullJourney_syncUpdateReschedulesOverlayTiming() async throws {
        env.preferencesManager.setOverlayShowMinutesBefore(0)
        env.preferencesManager.setPlayAlertSound(false)

        // Step 1: Initial sync with event at +30 minutes
        let initialEvent = E2EEventBuilder.futureEvent(
            id: "e2e-sync-journey",
            title: "Original Title",
            minutesFromNow: 30,
            calendarId: "sync-journey-cal",
        )
        try await env.databaseManager.replaceEvents(for: "sync-journey-cal", with: [initialEvent])

        let firstFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: firstFetch, overlayManager: env.overlayManager,
        )

        // Verify alert is far in the future
        let initialAlert = try XCTUnwrap(env.eventScheduler.scheduledAlerts.first)
        let initialLeadTime = initialAlert.triggerDate.timeIntervalSince(env.testClock.currentTime)
        XCTAssertGreaterThan(initialLeadTime, 20 * 60, "Alert should be ~30 minutes away")

        // Step 2: Sync update — event moved to 1 minute from now
        let updatedEvent = E2EEventBuilder.futureEvent(
            id: "e2e-sync-journey",
            title: "Updated Title",
            minutesFromNow: 1,
            calendarId: "sync-journey-cal",
        )
        try await env.databaseManager.replaceEvents(for: "sync-journey-cal", with: [updatedEvent])

        // Step 3: Re-schedule (as AppState.rescheduleEventsAfterSync would)
        env.eventScheduler.stopScheduling()

        let secondFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: secondFetch, overlayManager: env.overlayManager,
        )

        // Step 4: Wait for monitoring loop to fire overlay
        await env.waitForOverlay()

        let activeEvent = try XCTUnwrap(env.overlayManager.activeEvent)
        XCTAssertEqual(activeEvent.id, "e2e-sync-journey")
        XCTAssertEqual(activeEvent.title, "Updated Title")

        // Step 5: User dismisses
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
    }

    // MARK: - Full Journey: Snooze Survives Preference Change

    func testFullJourney_snoozeAcrossPreferenceChange() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-pref-change-journey",
            title: "Pref Change Meeting",
            minutesFromNow: 20,
            durationMinutes: 60,
        )
        try await env.seedAndSchedule([event])

        // Step 1: Overlay shows
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        // Step 2: User snoozes
        env.overlayManager.snoozeOverlay(for: 3)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Step 3: User changes preferences mid-snooze
        env.preferencesManager.setOverlayShowMinutesBefore(5)
        env.preferencesManager.setPlayAlertSound(false)
        await Task.yield() // Let Combine observer fire

        // Step 4: Snooze alert should survive preference change
        let snoozeAlert = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType, alert.event.id == event.id { return true }
                return false
            },
            "Snooze should survive preference change rescheduling",
        )

        // Step 5: Re-fire works
        env.overlayManager.showOverlayImmediately(for: snoozeAlert.event, fromSnooze: true)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)

        // Step 6: Final dismiss
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
    }

    // MARK: - Full Journey: Back-to-Back Meetings

    func testFullJourney_backToBackMeetingTransition() async throws {
        env.preferencesManager.setOverlayShowMinutesBefore(0)

        let event1 = E2EEventBuilder.futureEvent(
            id: "e2e-b2b-1",
            title: "Back-to-Back First",
            minutesFromNow: 1,
            durationMinutes: 30,
        )
        let event2 = E2EEventBuilder.futureEvent(
            id: "e2e-b2b-2",
            title: "Back-to-Back Second",
            minutesFromNow: 2,
            durationMinutes: 30,
        )
        try await env.seedAndSchedule([event1, event2])

        // Step 1: First meeting overlay
        env.overlayManager.showOverlayImmediately(for: event1)
        XCTAssertEqual(env.overlayManager.activeEvent?.title, "Back-to-Back First")

        // Step 2: User dismisses
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Step 3: Second meeting overlay
        env.overlayManager.showOverlayImmediately(for: event2)
        XCTAssertEqual(env.overlayManager.activeEvent?.title, "Back-to-Back Second")

        // Step 4: User dismisses
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)
    }

    // MARK: - Full Journey: Calendar Disconnection Cleans Up

    func testFullJourney_disconnectCleansUpScheduler() async throws {
        // Step 1: Events are scheduled
        let events = E2EEventBuilder.eventBatch(count: 5, startingMinutesFromNow: 10)
        try await env.seedAndSchedule(events)

        let initialAlertCount = env.eventScheduler.scheduledAlerts.count
        XCTAssertGreaterThanOrEqual(initialAlertCount, 5)

        // Step 2: Show overlay for first event
        let upcomingEvents = try await env.fetchUpcomingEvents()
        let firstEvent = try XCTUnwrap(upcomingEvents.first)
        env.overlayManager.showOverlayImmediately(for: firstEvent)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        // Step 3: Simulate disconnection (what AppState.disconnectFromCalendar does)
        env.eventScheduler.stopScheduling()
        env.overlayManager.hideOverlay()

        // Step 4: Verify clean state
        XCTAssertEqual(env.eventScheduler.scheduledAlerts, [])
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)

        // Step 5: Events still in DB but scheduler is idle
        let dbEvents = try await env.fetchUpcomingEvents()
        XCTAssertGreaterThanOrEqual(dbEvents.count, 5, "Events remain in DB after disconnect")
    }

    // MARK: - Full Journey: Rich Event Data Through Full Pipeline

    func testFullJourney_richEventDataPreservedThroughPipeline() async throws {
        env.preferencesManager.setOverlayShowMinutesBefore(0)

        // Step 1: Create event with all fields populated
        let richEvent = try Event(
            id: "e2e-rich-journey",
            title: "Quarterly Review with Leadership",
            startDate: Date().addingTimeInterval(60),
            endDate: Date().addingTimeInterval(3660),
            organizer: "cto@company.com",
            description: "Q4 performance review and Q1 planning",
            location: "Conference Room Alpha",
            attendees: [
                Attendee(
                    name: "Alice",
                    email: "alice@company.com",
                    status: .accepted,
                    isSelf: false,
                ),
                Attendee(
                    name: "Bob",
                    email: "bob@company.com",
                    status: .tentative,
                    isSelf: false,
                ),
            ],
            isAllDay: false,
            calendarId: "e2e-rich-cal",
            links: [XCTUnwrap(URL(string: "https://meet.google.com/rich-test"))],
            provider: .meet,
            createdAt: Date(),
            updatedAt: Date(),
        )

        // Step 2: Save to DB and schedule (with monitoring for waitForOverlay)
        try await env.seedAndSchedule([richEvent], startMonitoring: true)

        // Step 3: Wait for monitoring loop to fire overlay
        await env.waitForOverlay()

        // Step 4: Verify all data survived DB → scheduler → overlay pipeline
        let active = try XCTUnwrap(env.overlayManager.activeEvent)
        XCTAssertEqual(active.id, richEvent.id)
        XCTAssertEqual(active.title, "Quarterly Review with Leadership")
        XCTAssertEqual(active.organizer, "cto@company.com")
        XCTAssertEqual(active.calendarId, "e2e-rich-cal")
        XCTAssertEqual(active.provider, .meet)
        XCTAssertTrue(LinkParser().isOnlineMeeting(active))

        let link = try XCTUnwrap(LinkParser().primaryLink(for: active))
        XCTAssertEqual(link.host, "meet.google.com")

        XCTAssertEqual(
            Set(active.attendees.map(\.email)),
            Set(["alice@company.com", "bob@company.com"]),
        )

        // Step 5: User dismisses
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
    }

    // MARK: - Full Journey: Overlay Functional During Sync

    func testFullJourney_overlayFunctionalDuringSyncUpdate() async throws {
        // Step 1: Schedule event and show overlay
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-sync-during",
            title: "Meeting During Sync",
            minutesFromNow: 15,
            calendarId: "sync-during-cal",
        )
        try await env.seedAndSchedule([event])
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        // Step 2: Sync happens while overlay is visible
        let newEvents = [
            event,
            E2EEventBuilder.futureEvent(
                id: "e2e-sync-new",
                title: "New After Sync",
                minutesFromNow: 30,
                calendarId: "sync-during-cal",
            ),
        ]
        try await env.databaseManager.replaceEvents(for: "sync-during-cal", with: newEvents)

        // Step 3: Reschedule (as production does after sync)
        let fetched = try await env.fetchUpcomingEvents()
        env.eventScheduler.stopScheduling()
        await env.eventScheduler.startScheduling(
            events: fetched, overlayManager: env.overlayManager,
        )

        // Step 4: Overlay still visible and functional
        XCTAssertTrue(env.overlayManager.isOverlayVisible, "Overlay survives sync")
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)

        // Step 5: User can still snooze
        env.overlayManager.snoozeOverlay(for: 5)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Step 6: New event from sync is also scheduled
        let hasNewEvent = env.eventScheduler.scheduledAlerts.contains { $0.event.id == "e2e-sync-new" }
        XCTAssertTrue(hasNewEvent, "New event from sync should be scheduled")
    }
}
