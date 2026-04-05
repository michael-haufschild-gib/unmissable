import Foundation
import Testing
@testable import Unmissable

/// E2E tests for the calendar sync flow at the database boundary.
/// Tests the data pipeline that runs after API responses arrive:
/// events → DB save → scheduler update → overlay trigger.
/// The OAuth/network layer requires real credentials and is tested separately.
@MainActor
struct CalendarSyncE2ETests {
    private let env: E2ETestEnvironment

    init() async throws {
        env = try await E2ETestEnvironment()
    }

    // MARK: - Simulated Sync: New Events Arrive

    @Test
    func newEventsFromSyncAreScheduled() async throws {
        // Simulate what happens when sync brings new events
        let syncedEvents = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "sync-new-\(i)",
                title: "Synced Meeting \(i)",
                minutesFromNow: 15 + (i * 10),
                calendarId: "synced-calendar",
            )
        }

        // Save events (as SyncManager would after API call)
        try await env.databaseManager.replaceEvents(for: "synced-calendar", with: syncedEvents)

        // Fetch and schedule (as CalendarService would trigger)
        let upcoming = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: upcoming, overlayManager: env.overlayManager,
        )

        let scheduledIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        #expect(scheduledIds == Set(syncedEvents.map(\.id)))
    }

    // MARK: - Simulated Sync: Events Updated

    @Test
    func updatedEventsFromSyncRescheduleCorrectly() async throws {
        // Initial sync
        let initialEvents = [
            E2EEventBuilder.futureEvent(
                id: "sync-update-1",
                title: "Original Title",
                minutesFromNow: 30,
                calendarId: "sync-cal",
            ),
        ]
        try await env.databaseManager.replaceEvents(for: "sync-cal", with: initialEvents)

        let firstFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: firstFetch, overlayManager: env.overlayManager,
        )

        let initialAlertTrigger = env.eventScheduler.scheduledAlerts.first?.triggerDate

        // Second sync: event time changed (moved 15 min later)
        let updatedEvents = [
            E2EEventBuilder.futureEvent(
                id: "sync-update-1",
                title: "Updated Title",
                minutesFromNow: 45,
                calendarId: "sync-cal",
            ),
        ]
        try await env.databaseManager.replaceEvents(for: "sync-cal", with: updatedEvents)

        // Re-fetch and re-schedule
        env.eventScheduler.stopScheduling()
        let secondFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: secondFetch, overlayManager: env.overlayManager,
        )

        let updatedAlert = try #require(env.eventScheduler.scheduledAlerts.first)
        #expect(updatedAlert.event.title == "Updated Title")

        // Alert trigger time should have changed
        if let initialTrigger = initialAlertTrigger {
            #expect(
                updatedAlert.triggerDate != initialTrigger,
                "Alert should be rescheduled when event time changes",
            )
        }
    }

    // MARK: - Simulated Sync: Events Deleted

    @Test
    func deletedEventsFromSyncRemoveAlerts() async throws {
        // Initial sync with 3 events
        let initialEvents = E2EEventBuilder.eventBatch(
            count: 3, startingMinutesFromNow: 15, calendarId: "sync-delete-cal",
        )
        try await env.databaseManager.replaceEvents(for: "sync-delete-cal", with: initialEvents)

        let firstFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: firstFetch, overlayManager: env.overlayManager,
        )
        let initialAlertIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        #expect(initialAlertIds == Set(["e2e-batch-0", "e2e-batch-1", "e2e-batch-2"]))

        // Second sync: only 1 event remains (2 were cancelled)
        let remainingEvents = [
            E2EEventBuilder.futureEvent(
                id: "e2e-batch-0",
                title: "Only Remaining Meeting",
                minutesFromNow: 15,
                calendarId: "sync-delete-cal",
            ),
        ]
        try await env.databaseManager.replaceEvents(for: "sync-delete-cal", with: remainingEvents)

        // Re-schedule
        env.eventScheduler.stopScheduling()
        let secondFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: secondFetch, overlayManager: env.overlayManager,
        )

        let remainingAlertIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        #expect(remainingAlertIds == ["e2e-batch-0"], "Only the surviving event should have alerts")
    }

    // MARK: - Calendar Selection Changes

    @Test
    func calendarDeselectionRemovesItsEvents() async throws {
        let cal1Events = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-cal-sel-1-\(i)",
                minutesFromNow: 10 + (i * 5),
                calendarId: "selected-cal",
            )
        }
        let cal2Events = (0 ..< 2).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-cal-sel-2-\(i)",
                minutesFromNow: 12 + (i * 5),
                calendarId: "deselected-cal",
            )
        }

        try await env.seedEvents(cal1Events + cal2Events)

        // Schedule all events initially
        let allEvents = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: allEvents, overlayManager: env.overlayManager,
        )
        let initialCalendarIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.calendarId))
        #expect(initialCalendarIds == Set(["selected-cal", "deselected-cal"]))

        // Simulate deselecting "deselected-cal" by deleting its events
        try await env.databaseManager.deleteEventsForCalendar("deselected-cal")

        // Re-schedule with only remaining events
        env.eventScheduler.stopScheduling()
        let remaining = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: remaining, overlayManager: env.overlayManager,
        )

        let afterCalendarIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.calendarId))
        #expect(afterCalendarIds == Set(["selected-cal"]))
        let remainingAlertIds = env.eventScheduler.scheduledAlerts.map(\.event.id).sorted()
        #expect(remainingAlertIds == ["e2e-cal-sel-1-0", "e2e-cal-sel-1-1", "e2e-cal-sel-1-2"])
    }

    // MARK: - Calendar Metadata Persistence

    @Test
    func calendarInfoSavedAndFetchedCorrectly() async throws {
        let calendars = [
            CalendarInfo(
                id: "cal-1",
                name: "Work Calendar",
                description: "Work meetings",
                isSelected: true,
                isPrimary: true,
                colorHex: "#1a73e8",
                lastSyncAt: Date(),
                createdAt: Date(),
                updatedAt: Date(),
            ),
            CalendarInfo(
                id: "cal-2",
                name: "Personal Calendar",
                description: "Personal events",
                isSelected: false,
                isPrimary: false,
                colorHex: "#e67c73",
                lastSyncAt: Date(),
                createdAt: Date(),
                updatedAt: Date(),
            ),
        ]

        try await env.seedCalendars(calendars)

        let fetched = try await env.databaseManager.fetchCalendars()
        #expect(Set(fetched.map(\.id)) == Set(["cal-1", "cal-2"]))

        let workCal = try #require(fetched.first { $0.id == "cal-1" })
        #expect(workCal.name == "Work Calendar")
        #expect(workCal.isSelected)
        #expect(workCal.isPrimary)

        let personalCal = try #require(fetched.first { $0.id == "cal-2" })
        #expect(personalCal.name == "Personal Calendar")
        #expect(!personalCal.isSelected)
        #expect(!personalCal.isPrimary)
    }

    // MARK: - Sync With No Changes Is Idempotent

    @Test
    func repeatedSyncWithSameDataIsIdempotent() async throws {
        let events = E2EEventBuilder.eventBatch(
            count: 3, startingMinutesFromNow: 20, calendarId: "idempotent-cal",
        )

        // First sync
        try await env.databaseManager.replaceEvents(for: "idempotent-cal", with: events)
        let firstFetch = try await env.fetchUpcomingEvents()
        #expect(firstFetch.map(\.id) == ["e2e-batch-0", "e2e-batch-1", "e2e-batch-2"])

        // Second sync with same data
        try await env.databaseManager.replaceEvents(for: "idempotent-cal", with: events)
        let secondFetch = try await env.fetchUpcomingEvents()
        #expect(secondFetch.map(\.id) == ["e2e-batch-0", "e2e-batch-1", "e2e-batch-2"])

        // Event data should be identical
        for (first, second) in zip(firstFetch, secondFetch) {
            #expect(first.id == second.id)
            #expect(first.title == second.title)
        }
    }

    // MARK: - CalendarService Initialization Without OAuth

    @Test
    func calendarServiceInitializesDisconnected() {
        let calendarService = CalendarService(
            preferencesManager: env.preferencesManager,
            databaseManager: env.databaseManager,
            linkParser: LinkParser(),
        )

        #expect(!calendarService.isConnected)
        #expect(calendarService.syncStatus == .idle)
        #expect(calendarService.events.isEmpty)
        #expect(calendarService.calendars.isEmpty)
        #expect(calendarService.userEmail == nil)
    }

    @Test
    func calendarServiceDisconnectClearsState() async {
        let calendarService = CalendarService(
            preferencesManager: env.preferencesManager,
            databaseManager: env.databaseManager,
            linkParser: LinkParser(),
        )

        // Manually set some state
        calendarService.calendars = [
            CalendarInfo(id: "test", name: "Test", isSelected: true, isPrimary: false),
        ]

        await calendarService.disconnectAll()

        #expect(!calendarService.isConnected)
        #expect(calendarService.events.isEmpty)
    }
}
