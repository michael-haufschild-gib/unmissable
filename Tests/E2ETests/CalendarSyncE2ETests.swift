import Foundation
@testable import Unmissable
import XCTest

/// E2E tests for the calendar sync flow at the database boundary.
/// Tests the data pipeline that runs after API responses arrive:
/// events → DB save → scheduler update → overlay trigger.
/// The OAuth/network layer requires real credentials and is tested separately.
@MainActor
final class CalendarSyncE2ETests: XCTestCase {
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

    // MARK: - Simulated Sync: New Events Arrive

    func testNewEventsFromSyncAreScheduled() async throws {
        // Simulate what happens when sync brings new events
        let syncedEvents = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "sync-new-\(i)",
                title: "Synced Meeting \(i)",
                minutesFromNow: 15 + (i * 10),
                calendarId: "synced-calendar"
            )
        }

        // Save events (as SyncManager would after API call)
        try await env.databaseManager.replaceEvents(for: "synced-calendar", with: syncedEvents)

        // Fetch and schedule (as CalendarService would trigger)
        let upcoming = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: upcoming, overlayManager: env.overlayManager
        )

        XCTAssertEqual(env.eventScheduler.scheduledAlerts.count, 3)
        for event in syncedEvents {
            let hasAlert = env.eventScheduler.scheduledAlerts.contains { $0.event.id == event.id }
            XCTAssertTrue(hasAlert, "Synced event \(event.id) should be scheduled")
        }
    }

    // MARK: - Simulated Sync: Events Updated

    func testUpdatedEventsFromSyncRescheduleCorrectly() async throws {
        // Initial sync
        let initialEvents = [
            E2EEventBuilder.futureEvent(
                id: "sync-update-1",
                title: "Original Title",
                minutesFromNow: 30,
                calendarId: "sync-cal"
            ),
        ]
        try await env.databaseManager.replaceEvents(for: "sync-cal", with: initialEvents)

        let firstFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: firstFetch, overlayManager: env.overlayManager
        )

        let initialAlertTrigger = env.eventScheduler.scheduledAlerts.first?.triggerDate

        // Second sync: event time changed (moved 15 min later)
        let updatedEvents = [
            E2EEventBuilder.futureEvent(
                id: "sync-update-1",
                title: "Updated Title",
                minutesFromNow: 45,
                calendarId: "sync-cal"
            ),
        ]
        try await env.databaseManager.replaceEvents(for: "sync-cal", with: updatedEvents)

        // Re-fetch and re-schedule
        env.eventScheduler.stopScheduling()
        let secondFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: secondFetch, overlayManager: env.overlayManager
        )

        let updatedAlert = try XCTUnwrap(env.eventScheduler.scheduledAlerts.first)
        XCTAssertEqual(updatedAlert.event.title, "Updated Title")

        // Alert trigger time should have changed
        if let initialTrigger = initialAlertTrigger {
            XCTAssertNotEqual(
                updatedAlert.triggerDate, initialTrigger,
                "Alert should be rescheduled when event time changes"
            )
        }
    }

    // MARK: - Simulated Sync: Events Deleted

    func testDeletedEventsFromSyncRemoveAlerts() async throws {
        // Initial sync with 3 events
        let initialEvents = E2EEventBuilder.eventBatch(
            count: 3, startingMinutesFromNow: 15, calendarId: "sync-delete-cal"
        )
        try await env.databaseManager.replaceEvents(for: "sync-delete-cal", with: initialEvents)

        let firstFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: firstFetch, overlayManager: env.overlayManager
        )
        XCTAssertEqual(env.eventScheduler.scheduledAlerts.count, 3)

        // Second sync: only 1 event remains (2 were cancelled)
        let remainingEvents = [
            E2EEventBuilder.futureEvent(
                id: "e2e-batch-0",
                title: "Only Remaining Meeting",
                minutesFromNow: 15,
                calendarId: "sync-delete-cal"
            ),
        ]
        try await env.databaseManager.replaceEvents(for: "sync-delete-cal", with: remainingEvents)

        // Re-schedule
        env.eventScheduler.stopScheduling()
        let secondFetch = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: secondFetch, overlayManager: env.overlayManager
        )

        XCTAssertEqual(env.eventScheduler.scheduledAlerts.count, 1)
        XCTAssertEqual(env.eventScheduler.scheduledAlerts.first?.event.id, "e2e-batch-0")
    }

    // MARK: - Calendar Selection Changes

    func testCalendarDeselectionRemovesItsEvents() async throws {
        let cal1Events = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-cal-sel-1-\(i)",
                minutesFromNow: 10 + (i * 5),
                calendarId: "selected-cal"
            )
        }
        let cal2Events = (0 ..< 2).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-cal-sel-2-\(i)",
                minutesFromNow: 12 + (i * 5),
                calendarId: "deselected-cal"
            )
        }

        try await env.seedEvents(cal1Events + cal2Events)

        // Schedule all events initially
        let allEvents = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: allEvents, overlayManager: env.overlayManager
        )
        XCTAssertEqual(env.eventScheduler.scheduledAlerts.count, 5)

        // Simulate deselecting "deselected-cal" by deleting its events
        try await env.databaseManager.deleteEventsForCalendar("deselected-cal")

        // Re-schedule with only remaining events
        env.eventScheduler.stopScheduling()
        let remaining = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: remaining, overlayManager: env.overlayManager
        )

        XCTAssertEqual(env.eventScheduler.scheduledAlerts.count, 3)
        let alertCalendarIds = Set(
            env.eventScheduler.scheduledAlerts.map(\.event.calendarId)
        )
        XCTAssertEqual(alertCalendarIds, ["selected-cal"])
    }

    // MARK: - Calendar Metadata Persistence

    func testCalendarInfoSavedAndFetchedCorrectly() async throws {
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
                updatedAt: Date()
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
                updatedAt: Date()
            ),
        ]

        try await env.seedCalendars(calendars)

        let fetched = try await env.databaseManager.fetchCalendars()
        XCTAssertEqual(fetched.count, 2)

        let workCal = try XCTUnwrap(fetched.first { $0.id == "cal-1" })
        XCTAssertEqual(workCal.name, "Work Calendar")
        XCTAssertTrue(workCal.isSelected)
        XCTAssertTrue(workCal.isPrimary)

        let personalCal = try XCTUnwrap(fetched.first { $0.id == "cal-2" })
        XCTAssertEqual(personalCal.name, "Personal Calendar")
        XCTAssertFalse(personalCal.isSelected)
        XCTAssertFalse(personalCal.isPrimary)
    }

    // MARK: - Sync With No Changes Is Idempotent

    func testRepeatedSyncWithSameDataIsIdempotent() async throws {
        let events = E2EEventBuilder.eventBatch(
            count: 3, startingMinutesFromNow: 20, calendarId: "idempotent-cal"
        )

        // First sync
        try await env.databaseManager.replaceEvents(for: "idempotent-cal", with: events)
        let firstFetch = try await env.fetchUpcomingEvents()
        XCTAssertEqual(firstFetch.count, 3)

        // Second sync with same data
        try await env.databaseManager.replaceEvents(for: "idempotent-cal", with: events)
        let secondFetch = try await env.fetchUpcomingEvents()
        XCTAssertEqual(secondFetch.count, 3)

        // Event data should be identical
        for (first, second) in zip(firstFetch, secondFetch) {
            XCTAssertEqual(first.id, second.id)
            XCTAssertEqual(first.title, second.title)
        }
    }

    // MARK: - CalendarService Initialization Without OAuth

    func testCalendarServiceInitializesDisconnected() {
        let calendarService = CalendarService(
            preferencesManager: env.preferencesManager,
            databaseManager: env.databaseManager
        )

        XCTAssertFalse(calendarService.isConnected)
        XCTAssertEqual(calendarService.syncStatus, .idle)
        XCTAssertTrue(calendarService.events.isEmpty)
        XCTAssertTrue(calendarService.calendars.isEmpty)
        XCTAssertNil(calendarService.userEmail)
    }

    func testCalendarServiceDisconnectClearsState() {
        let calendarService = CalendarService(
            preferencesManager: env.preferencesManager,
            databaseManager: env.databaseManager
        )

        // Manually set some state
        calendarService.calendars = [
            CalendarInfo(id: "test", name: "Test", isSelected: true, isPrimary: false),
        ]

        calendarService.disconnectAll()

        XCTAssertFalse(calendarService.isConnected)
        XCTAssertTrue(calendarService.events.isEmpty)
    }
}
