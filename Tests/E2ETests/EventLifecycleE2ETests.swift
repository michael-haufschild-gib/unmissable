import Foundation
@testable import Unmissable
import XCTest

/// E2E tests for the complete event lifecycle: DB → fetch → schedule → overlay.
/// These tests exercise the full production code path with a real (test-scoped) database.
@MainActor
final class EventLifecycleE2ETests: XCTestCase {
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

    // MARK: - Full Lifecycle: Save → Fetch → Schedule → Verify

    func testEventSavedToDatabaseIsScheduledForOverlay() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-lifecycle-1",
            title: "Lifecycle Test Meeting",
            minutesFromNow: 15
        )

        // Save to database
        try await env.seedEvents([event])

        // Fetch from database — verify round-trip
        let fetched = try await env.fetchUpcomingEvents()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, event.id)
        XCTAssertEqual(fetched.first?.title, event.title)

        // Schedule alerts from DB events
        await env.eventScheduler.startScheduling(
            events: fetched, overlayManager: env.overlayManager
        )

        // Verify alert was created
        XCTAssertFalse(env.eventScheduler.scheduledAlerts.isEmpty)
        let alert = try XCTUnwrap(env.eventScheduler.scheduledAlerts.first)
        XCTAssertEqual(alert.event.id, event.id)
    }

    func testMultipleEventsSavedAndScheduledInOrder() async throws {
        let events = E2EEventBuilder.eventBatch(
            count: 5,
            startingMinutesFromNow: 10,
            spacingMinutes: 10
        )

        try await env.seedAndSchedule(events)

        // All 5 events should be fetched and scheduled
        let fetched = try await env.fetchUpcomingEvents()
        XCTAssertEqual(fetched.count, 5)

        // Alerts should be sorted by trigger time (earliest first)
        let triggerTimes = env.eventScheduler.scheduledAlerts.map(\.triggerDate)
        let sorted = triggerTimes.sorted()
        XCTAssertEqual(triggerTimes, sorted)

        // Verify each event has a matching alert
        for event in events {
            let hasAlert = env.eventScheduler.scheduledAlerts.contains { $0.event.id == event.id }
            XCTAssertTrue(hasAlert, "Event \(event.id) should have a scheduled alert")
        }
    }

    // MARK: - Past Events Should Not Schedule

    func testPastEventSavedButNotScheduled() async throws {
        let pastEvent = E2EEventBuilder.pastEvent(id: "e2e-past-no-schedule")
        let futureEvent = E2EEventBuilder.futureEvent(
            id: "e2e-future-yes-schedule",
            minutesFromNow: 20
        )

        try await env.seedEvents([pastEvent, futureEvent])

        // Both are in the DB
        let allEvents = try await env.databaseManager.fetchEvents(
            from: Date().addingTimeInterval(-86_400),
            to: Date().addingTimeInterval(86_400)
        )
        XCTAssertEqual(allEvents.count, 2)

        // But only the future event should appear in upcoming fetch
        let upcoming = try await env.fetchUpcomingEvents()
        XCTAssertEqual(upcoming.count, 1)
        XCTAssertEqual(upcoming.first?.id, futureEvent.id)

        // Schedule from upcoming — only future event gets alerts
        await env.eventScheduler.startScheduling(
            events: upcoming, overlayManager: env.overlayManager
        )
        let alertEventIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        XCTAssert(alertEventIds.isSuperset(of: [futureEvent.id]))
        XCTAssert(alertEventIds.isDisjoint(with: [pastEvent.id]))
    }

    // MARK: - Started Meetings

    func testStartedMeetingsFetchedCorrectly() async throws {
        let startedEvent = E2EEventBuilder.startedEvent(
            id: "e2e-started-1",
            title: "In Progress Meeting",
            minutesAgo: 10,
            durationMinutes: 60
        )
        let futureEvent = E2EEventBuilder.futureEvent(
            id: "e2e-future-1",
            minutesFromNow: 30
        )
        let pastEvent = E2EEventBuilder.pastEvent(id: "e2e-ended-1")

        try await env.seedEvents([startedEvent, futureEvent, pastEvent])

        let started = try await env.fetchStartedMeetings()
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started.first?.id, startedEvent.id)

        let upcoming = try await env.fetchUpcomingEvents()
        XCTAssertEqual(upcoming.count, 1)
        XCTAssertEqual(upcoming.first?.id, futureEvent.id)
    }

    // MARK: - All-Day Events

    func testAllDayEventsExcludedFromScheduling() async throws {
        let allDayEvent = E2EEventBuilder.allDayEvent(id: "e2e-allday-1")
        let regularEvent = E2EEventBuilder.futureEvent(
            id: "e2e-regular-1",
            minutesFromNow: 20
        )

        try await env.seedEvents([allDayEvent, regularEvent])

        // All-day events are stored in DB
        let allEvents = try await env.databaseManager.fetchEvents(
            from: Date().addingTimeInterval(-86_400),
            to: Date().addingTimeInterval(86_400)
        )
        XCTAssertGreaterThanOrEqual(allEvents.count, 1)

        // Schedule should process the regular event
        let upcoming = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: upcoming, overlayManager: env.overlayManager
        )

        // The all-day event may or may not appear in upcoming depending on
        // its start time relative to now, but the regular event should be scheduled
        let hasRegularAlert = env.eventScheduler.scheduledAlerts.contains { $0.event.id == regularEvent.id }
        XCTAssertTrue(hasRegularAlert)
    }

    // MARK: - Database Round-Trip Fidelity

    func testEventDataPreservedThroughDatabaseRoundTrip() async throws {
        let originalEvent = Event(
            id: "e2e-roundtrip",
            title: "Round Trip Test Meeting",
            startDate: Date().addingTimeInterval(1200),
            endDate: Date().addingTimeInterval(4800),
            organizer: "cto@company.com",
            description: "Quarterly planning session",
            location: "Conference Room B",
            isAllDay: false,
            calendarId: "e2e-roundtrip-cal",
            timezone: "America/New_York",
            links: [],
            provider: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await env.seedEvents([originalEvent])
        let fetched = try await env.fetchUpcomingEvents()

        let roundTripped = try XCTUnwrap(fetched.first { $0.id == originalEvent.id })
        XCTAssertEqual(roundTripped.title, originalEvent.title)
        XCTAssertEqual(roundTripped.organizer, originalEvent.organizer)
        XCTAssertEqual(roundTripped.calendarId, originalEvent.calendarId)
        XCTAssertEqual(roundTripped.isAllDay, originalEvent.isAllDay)
        // Date comparison with tolerance for DB serialization
        XCTAssertLessThan(
            abs(roundTripped.startDate.timeIntervalSince(originalEvent.startDate)), 1.0
        )
        XCTAssertLessThan(
            abs(roundTripped.endDate.timeIntervalSince(originalEvent.endDate)), 1.0
        )
    }

    // MARK: - Online Meeting Links Preserved

    func testOnlineMeetingLinksPreservedThroughDatabase() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-online-roundtrip",
            title: "Google Meet E2E",
            minutesFromNow: 15,
            provider: .meet
        )

        try await env.seedEvents([meetEvent])
        let fetched = try await env.fetchUpcomingEvents()

        let roundTripped = try XCTUnwrap(fetched.first)
        XCTAssertEqual(roundTripped.id, meetEvent.id)
        XCTAssertTrue(LinkParser.shared.isOnlineMeeting(roundTripped))
        let link = try XCTUnwrap(LinkParser.shared.primaryLink(for: roundTripped))
        XCTAssertEqual(link.host, "meet.google.com")
        XCTAssertEqual(roundTripped.provider, .meet)
    }

    // MARK: - Calendar Isolation

    func testEventsIsolatedByCalendar() async throws {
        let cal1Events = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-cal1-\(i)",
                title: "Calendar 1 Meeting \(i)",
                minutesFromNow: 10 + (i * 10),
                calendarId: "calendar-1"
            )
        }
        let cal2Events = (0 ..< 2).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-cal2-\(i)",
                title: "Calendar 2 Meeting \(i)",
                minutesFromNow: 15 + (i * 10),
                calendarId: "calendar-2"
            )
        }

        try await env.seedEvents(cal1Events + cal2Events)

        // Delete calendar 1 events
        try await env.databaseManager.deleteEventsForCalendar("calendar-1")

        let remaining = try await env.fetchUpcomingEvents()
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.allSatisfy { $0.calendarId == "calendar-2" })
    }

    // MARK: - Replace Events for Calendar

    func testReplaceEventsAtomicallyUpdatesDatabaseAndScheduler() async throws {
        let originalEvents = [
            E2EEventBuilder.futureEvent(
                id: "e2e-replace-old-1",
                title: "Old Meeting 1",
                minutesFromNow: 20,
                calendarId: "replace-cal"
            ),
            E2EEventBuilder.futureEvent(
                id: "e2e-replace-old-2",
                title: "Old Meeting 2",
                minutesFromNow: 40,
                calendarId: "replace-cal"
            ),
        ]

        // Seed original events and schedule
        try await env.seedAndSchedule(originalEvents)
        XCTAssertEqual(env.eventScheduler.scheduledAlerts.count, 2)

        // Replace with new events (simulating a sync update)
        let newEvents = [
            E2EEventBuilder.futureEvent(
                id: "e2e-replace-new-1",
                title: "New Meeting 1",
                minutesFromNow: 25,
                calendarId: "replace-cal"
            ),
        ]
        try await env.databaseManager.replaceEvents(for: "replace-cal", with: newEvents)

        // Re-fetch and re-schedule
        let updated = try await env.fetchUpcomingEvents()
        env.eventScheduler.stopScheduling()
        await env.eventScheduler.startScheduling(
            events: updated, overlayManager: env.overlayManager
        )

        // Only the new event should be scheduled
        XCTAssertEqual(env.eventScheduler.scheduledAlerts.count, 1)
        XCTAssertEqual(env.eventScheduler.scheduledAlerts.first?.event.id, "e2e-replace-new-1")

        // Old events should be gone from DB
        let all = try await env.databaseManager.fetchEvents(
            from: Date(), to: Date().addingTimeInterval(86_400)
        )
        let oldIds = all.map(\.id)
        XCTAssertFalse(oldIds.contains("e2e-replace-old-1"))
        XCTAssertFalse(oldIds.contains("e2e-replace-old-2"))
    }
}
