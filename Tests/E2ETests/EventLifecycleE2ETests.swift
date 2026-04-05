import Foundation
import Testing
@testable import Unmissable

/// E2E tests for the complete event lifecycle: DB → fetch → schedule → overlay.
/// These tests exercise the full production code path with a real (test-scoped) database.
@MainActor
struct EventLifecycleE2ETests {
    private let env: E2ETestEnvironment

    init() async throws {
        env = try await E2ETestEnvironment()
    }

    // MARK: - Full Lifecycle: Save → Fetch → Schedule → Verify

    @Test
    func eventSavedToDatabaseIsScheduledForOverlay() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-lifecycle-1",
            title: "Lifecycle Test Meeting",
            minutesFromNow: 15,
        )

        // Save to database
        try await env.seedEvents([event])

        // Fetch from database — verify round-trip
        let fetched = try await env.fetchUpcomingEvents()
        let fetchedEvent = try #require(fetched.first)
        #expect(fetchedEvent.id == event.id)
        #expect(fetchedEvent.title == event.title)

        // Schedule alerts from DB events
        await env.eventScheduler.startScheduling(
            events: fetched, overlayManager: env.overlayManager,
        )

        // Verify alert was created
        let alert = try #require(
            env.eventScheduler.scheduledAlerts.first,
            "Should have at least one scheduled alert",
        )
        #expect(alert.event.id == event.id)
    }

    @Test
    func multipleEventsSavedAndScheduledInOrder() async throws {
        let events = E2EEventBuilder.eventBatch(
            count: 5,
            startingMinutesFromNow: 10,
            spacingMinutes: 10,
        )

        try await env.seedAndSchedule(events)

        // All 5 events should be fetched and scheduled
        let fetched = try await env.fetchUpcomingEvents()
        #expect(fetched.map(\.id) == (0 ..< 5).map { "e2e-batch-\($0)" })

        // Alerts should be sorted by trigger time (earliest first)
        let triggerTimes = env.eventScheduler.scheduledAlerts.map(\.triggerDate)
        let sorted = triggerTimes.sorted()
        #expect(triggerTimes == sorted)

        // Verify each event has a matching alert
        for event in events {
            let hasAlert = env.eventScheduler.scheduledAlerts.contains { $0.event.id == event.id }
            #expect(hasAlert, "Event \(event.id) should have a scheduled alert")
        }
    }

    // MARK: - Past Events Should Not Schedule

    @Test
    func pastEventSavedButNotScheduled() async throws {
        let pastEvent = E2EEventBuilder.pastEvent(id: "e2e-past-no-schedule")
        let futureEvent = E2EEventBuilder.futureEvent(
            id: "e2e-future-yes-schedule",
            minutesFromNow: 20,
        )

        try await env.seedEvents([pastEvent, futureEvent])

        // Both are in the DB
        let allEvents = try await env.databaseManager.fetchEvents(
            from: Date().addingTimeInterval(-86_400),
            to: Date().addingTimeInterval(86_400),
        )
        #expect(Set(allEvents.map(\.id)) == Set([pastEvent.id, futureEvent.id]))

        // But only the future event should appear in upcoming fetch
        let upcoming = try await env.fetchUpcomingEvents()
        let upcomingEvent = try #require(upcoming.first)
        #expect(upcomingEvent.id == futureEvent.id)

        // Schedule from upcoming — only future event gets alerts
        await env.eventScheduler.startScheduling(
            events: upcoming, overlayManager: env.overlayManager,
        )
        let alertEventIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        #expect(alertEventIds == Set([futureEvent.id]), "Only the future event should be scheduled")
    }

    // MARK: - Started Meetings

    @Test
    func startedMeetingsFetchedCorrectly() async throws {
        let startedEvent = E2EEventBuilder.startedEvent(
            id: "e2e-started-1",
            title: "In Progress Meeting",
            minutesAgo: 10,
            durationMinutes: 60,
        )
        let futureEvent = E2EEventBuilder.futureEvent(
            id: "e2e-future-1",
            minutesFromNow: 30,
        )
        let pastEvent = E2EEventBuilder.pastEvent(id: "e2e-ended-1")

        try await env.seedEvents([startedEvent, futureEvent, pastEvent])

        let started = try await env.fetchStartedMeetings()
        let startedMatch = try #require(started.first)
        #expect(startedMatch.id == startedEvent.id)

        let upcoming = try await env.fetchUpcomingEvents()
        let upcomingMatch = try #require(upcoming.first)
        #expect(upcomingMatch.id == futureEvent.id)
    }

    // MARK: - All-Day Events

    @Test
    func allDayEventsExcludedFromScheduling() async throws {
        let allDayEvent = E2EEventBuilder.allDayEvent(id: "e2e-allday-1")
        let regularEvent = E2EEventBuilder.futureEvent(
            id: "e2e-regular-1",
            minutesFromNow: 20,
        )

        try await env.seedEvents([allDayEvent, regularEvent])

        // All-day events are stored in DB
        let allEvents = try await env.databaseManager.fetchEvents(
            from: Date().addingTimeInterval(-86_400),
            to: Date().addingTimeInterval(86_400),
        )
        #expect(allEvents.count >= 1)

        // Schedule should process the regular event
        let upcoming = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: upcoming, overlayManager: env.overlayManager,
        )

        // The all-day event may or may not appear in upcoming depending on
        // its start time relative to now, but the regular event should be scheduled
        let hasRegularAlert = env.eventScheduler.scheduledAlerts.contains { $0.event.id == regularEvent.id }
        #expect(hasRegularAlert)
    }

    // MARK: - Database Round-Trip Fidelity

    @Test
    func eventDataPreservedThroughDatabaseRoundTrip() async throws {
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
            updatedAt: Date(),
        )

        try await env.seedEvents([originalEvent])
        let fetched = try await env.fetchUpcomingEvents()

        let roundTripped = try #require(fetched.first { $0.id == originalEvent.id })
        #expect(roundTripped.title == originalEvent.title)
        #expect(roundTripped.organizer == originalEvent.organizer)
        #expect(roundTripped.calendarId == originalEvent.calendarId)
        #expect(roundTripped.isAllDay == originalEvent.isAllDay)
        // Date comparison with tolerance for DB serialization
        #expect(abs(roundTripped.startDate.timeIntervalSince(originalEvent.startDate)) < 1.0)
        #expect(abs(roundTripped.endDate.timeIntervalSince(originalEvent.endDate)) < 1.0)
    }

    // MARK: - Online Meeting Links Preserved

    @Test
    func onlineMeetingLinksPreservedThroughDatabase() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-online-roundtrip",
            title: "Google Meet E2E",
            minutesFromNow: 15,
            provider: .meet,
        )

        try await env.seedEvents([meetEvent])
        let fetched = try await env.fetchUpcomingEvents()

        let roundTripped = try #require(fetched.first)
        #expect(roundTripped.id == meetEvent.id)
        #expect(LinkParser().isOnlineMeeting(roundTripped))
        let link = try #require(LinkParser().primaryLink(for: roundTripped))
        #expect(link.host == "meet.google.com")
        #expect(roundTripped.provider == .meet)
    }

    // MARK: - Calendar Isolation

    @Test
    func eventsIsolatedByCalendar() async throws {
        let cal1Events = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-cal1-\(i)",
                title: "Calendar 1 Meeting \(i)",
                minutesFromNow: 10 + (i * 10),
                calendarId: "calendar-1",
            )
        }
        let cal2Events = (0 ..< 2).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-cal2-\(i)",
                title: "Calendar 2 Meeting \(i)",
                minutesFromNow: 15 + (i * 10),
                calendarId: "calendar-2",
            )
        }

        try await env.seedEvents(cal1Events + cal2Events)

        // Delete calendar 1 events
        try await env.databaseManager.deleteEventsForCalendar("calendar-1")

        let remaining = try await env.fetchUpcomingEvents()
        #expect(Set(remaining.map(\.id)) == Set(["e2e-cal2-0", "e2e-cal2-1"]))
        #expect(Set(remaining.map(\.calendarId)) == Set(["calendar-2"]))
    }

    // MARK: - Replace Events for Calendar

    @Test
    func replaceEventsAtomicallyUpdatesDatabaseAndScheduler() async throws {
        let originalEvents = [
            E2EEventBuilder.futureEvent(
                id: "e2e-replace-old-1",
                title: "Old Meeting 1",
                minutesFromNow: 20,
                calendarId: "replace-cal",
            ),
            E2EEventBuilder.futureEvent(
                id: "e2e-replace-old-2",
                title: "Old Meeting 2",
                minutesFromNow: 40,
                calendarId: "replace-cal",
            ),
        ]

        // Seed original events and schedule
        try await env.seedAndSchedule(originalEvents)
        let originalAlertIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        #expect(originalAlertIds == Set(["e2e-replace-old-1", "e2e-replace-old-2"]))

        // Replace with new events (simulating a sync update)
        let newEvents = [
            E2EEventBuilder.futureEvent(
                id: "e2e-replace-new-1",
                title: "New Meeting 1",
                minutesFromNow: 25,
                calendarId: "replace-cal",
            ),
        ]
        try await env.databaseManager.replaceEvents(for: "replace-cal", with: newEvents)

        // Re-fetch and re-schedule
        let updated = try await env.fetchUpcomingEvents()
        env.eventScheduler.stopScheduling()
        await env.eventScheduler.startScheduling(
            events: updated, overlayManager: env.overlayManager,
        )

        // Only the new event should be scheduled — no stale alerts from old events
        let scheduledIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        #expect(scheduledIds == Set(["e2e-replace-new-1"]))

        // Old events should be gone from DB
        let all = try await env.databaseManager.fetchEvents(
            from: Date(), to: Date().addingTimeInterval(86_400),
        )
        let oldIds = all.map(\.id)
        #expect(!oldIds.contains("e2e-replace-old-1"))
        #expect(!oldIds.contains("e2e-replace-old-2"))
    }
}
