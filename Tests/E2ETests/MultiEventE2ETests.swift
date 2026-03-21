import Foundation
@testable import Unmissable
import XCTest

/// E2E tests for multi-event coordination, overlapping events, and edge cases
/// through the full stack with database persistence.
@MainActor
final class MultiEventE2ETests: XCTestCase {
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

    // MARK: - Overlapping Events

    func testOverlappingEventsAllScheduled() async throws {
        let baseTime = Date().addingTimeInterval(1200) // 20 minutes from now
        let overlapping = [
            Event(
                id: "e2e-overlap-1",
                title: "Meeting A",
                startDate: baseTime,
                endDate: baseTime.addingTimeInterval(3600),
                calendarId: "e2e-cal"
            ),
            Event(
                id: "e2e-overlap-2",
                title: "Meeting B",
                startDate: baseTime.addingTimeInterval(1800), // Starts 30 min into Meeting A
                endDate: baseTime.addingTimeInterval(5400),
                calendarId: "e2e-cal"
            ),
        ]

        try await env.seedAndSchedule(overlapping)

        // Both overlapping events should be scheduled
        let alertIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        XCTAssert(alertIds.isSuperset(of: ["e2e-overlap-1", "e2e-overlap-2"]))
        XCTAssertEqual(alertIds.count, 2)
    }

    func testOverlayReplacementForOverlappingEvents() async throws {
        let event1 = E2EEventBuilder.futureEvent(
            id: "e2e-overlap-show-1",
            title: "First Overlapping",
            minutesFromNow: 10
        )
        let event2 = E2EEventBuilder.futureEvent(
            id: "e2e-overlap-show-2",
            title: "Second Overlapping",
            minutesFromNow: 15
        )

        try await env.seedAndSchedule([event1, event2])

        // Show first event's overlay
        env.overlayManager.showOverlayImmediately(for: event1)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event1.id)

        // Show second event's overlay — should replace first
        env.overlayManager.showOverlayImmediately(for: event2)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event2.id)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
    }

    // MARK: - Events with Identical Start Times

    func testEventsWithIdenticalStartTimesAllScheduled() async throws {
        let sameTime = Date().addingTimeInterval(900) // 15 minutes from now
        let events = (0 ..< 3).map { i in
            Event(
                id: "e2e-same-time-\(i)",
                title: "Concurrent Meeting \(i)",
                startDate: sameTime,
                endDate: sameTime.addingTimeInterval(3600),
                calendarId: "e2e-cal"
            )
        }

        try await env.seedAndSchedule(events)

        // All events should have alerts
        let alertIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        let expectedIds = Set(events.map(\.id))
        XCTAssertEqual(alertIds.intersection(expectedIds), expectedIds)
    }

    // MARK: - Multiple Calendars

    func testEventsFromMultipleCalendarsScheduledTogether() async throws {
        let workEvents = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-work-\(i)",
                title: "Work Meeting \(i)",
                minutesFromNow: 20 + (i * 15),
                calendarId: "work-calendar"
            )
        }
        let personalEvents = (0 ..< 2).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-personal-\(i)",
                title: "Personal Event \(i)",
                minutesFromNow: 25 + (i * 20),
                calendarId: "personal-calendar"
            )
        }

        try await env.seedAndSchedule(workEvents + personalEvents)

        // All 5 events should be scheduled
        XCTAssertGreaterThanOrEqual(env.eventScheduler.scheduledAlerts.count, 5)

        // Verify interleaved ordering by trigger time
        let triggerTimes = env.eventScheduler.scheduledAlerts.map(\.triggerDate)
        XCTAssertEqual(triggerTimes, triggerTimes.sorted())
    }

    // MARK: - Large Batch Performance

    func testLargeBatchScheduledWithinPerformanceBudget() async throws {
        let events = E2EEventBuilder.eventBatch(
            count: 100,
            startingMinutesFromNow: 10,
            spacingMinutes: 5
        )

        try await env.seedEvents(events)

        let fetched = try await env.fetchUpcomingEvents(limit: 100)
        XCTAssertEqual(fetched.count, 100)

        let startTime = CFAbsoluteTimeGetCurrent()
        await env.eventScheduler.startScheduling(
            events: fetched, overlayManager: env.overlayManager
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 2.0, "Scheduling 100 events should complete in under 2 seconds")
        XCTAssertGreaterThanOrEqual(env.eventScheduler.scheduledAlerts.count, 100)
    }

    // MARK: - Sequential Overlay Through Multiple Events

    func testSequentialOverlayDismissalsForMultipleEvents() async throws {
        let events = E2EEventBuilder.eventBatch(
            count: 5,
            startingMinutesFromNow: 10,
            spacingMinutes: 10
        )

        try await env.seedAndSchedule(events)

        // Simulate sequential overlay flow: show → dismiss for each event
        for event in events {
            env.overlayManager.showOverlayImmediately(for: event)
            XCTAssertTrue(env.overlayManager.isOverlayVisible)
            XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)

            env.overlayManager.hideOverlay()
            XCTAssertFalse(env.overlayManager.isOverlayVisible)
            XCTAssertNil(env.overlayManager.activeEvent)
        }
    }

    func testSequentialSnoozesForMultipleEvents() async throws {
        let events = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-seq-snooze-\(i)",
                title: "Sequential Snooze Meeting \(i)",
                minutesFromNow: 15 + (i * 10)
            )
        }

        try await env.seedAndSchedule(events)

        for (index, event) in events.enumerated() {
            env.overlayManager.showOverlayImmediately(for: event)
            env.overlayManager.snoozeOverlay(for: 5)

            let snoozeAlerts = env.eventScheduler.scheduledAlerts.filter { alert in
                if case .snooze = alert.alertType, alert.event.id == event.id {
                    return true
                }
                return false
            }
            XCTAssertEqual(
                snoozeAlerts.count, 1,
                "Event \(index) should have exactly 1 snooze alert"
            )
        }
    }

    // MARK: - Mixed Event Types

    func testMixedEventTypesHandledCorrectly() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-mixed-meet",
            title: "Google Meet",
            minutesFromNow: 15,
            provider: .meet
        )
        let zoomEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-mixed-zoom",
            title: "Zoom Call",
            minutesFromNow: 30,
            provider: .zoom
        )
        let inPersonEvent = E2EEventBuilder.futureEvent(
            id: "e2e-mixed-inperson",
            title: "In-Person Meeting",
            minutesFromNow: 45
        )
        let allDayEvent = E2EEventBuilder.allDayEvent(
            id: "e2e-mixed-allday",
            title: "Team Offsite"
        )

        try await env.seedEvents([meetEvent, zoomEvent, inPersonEvent, allDayEvent])

        let upcoming = try await env.fetchUpcomingEvents(limit: 50)
        await env.eventScheduler.startScheduling(
            events: upcoming, overlayManager: env.overlayManager
        )

        // Online meetings should preserve their provider info
        let fetchedMeet = try XCTUnwrap(upcoming.first { $0.id == "e2e-mixed-meet" })
        XCTAssertTrue(LinkParser.shared.isOnlineMeeting(fetchedMeet))
        XCTAssertEqual(fetchedMeet.provider, .meet)

        let fetchedZoom = try XCTUnwrap(upcoming.first { $0.id == "e2e-mixed-zoom" })
        XCTAssertTrue(LinkParser.shared.isOnlineMeeting(fetchedZoom))
        XCTAssertEqual(fetchedZoom.provider, .zoom)

        // In-person meeting has no meeting link
        let fetchedInPerson = try XCTUnwrap(upcoming.first { $0.id == "e2e-mixed-inperson" })
        XCTAssertFalse(LinkParser.shared.isOnlineMeeting(fetchedInPerson))
    }

    // MARK: - Stop and Restart Scheduling

    func testStopAndRestartSchedulingCleansUpCorrectly() async throws {
        let events = E2EEventBuilder.eventBatch(count: 3, startingMinutesFromNow: 10)
        try await env.seedAndSchedule(events)

        XCTAssertEqual(env.eventScheduler.scheduledAlerts.count, 3)

        // Stop scheduling
        env.eventScheduler.stopScheduling()
        XCTAssertTrue(env.eventScheduler.scheduledAlerts.isEmpty)

        // Re-schedule with updated events
        let newEvent = E2EEventBuilder.futureEvent(
            id: "e2e-restart",
            title: "After Restart",
            minutesFromNow: 20
        )
        try await env.seedEvents([newEvent])

        let allUpcoming = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: allUpcoming, overlayManager: env.overlayManager
        )

        // Should have alerts for all events (original 3 + new 1)
        XCTAssertGreaterThanOrEqual(env.eventScheduler.scheduledAlerts.count, 4)

        let hasNewEvent = env.eventScheduler.scheduledAlerts.contains { $0.event.id == "e2e-restart" }
        XCTAssertTrue(hasNewEvent)
    }
}
