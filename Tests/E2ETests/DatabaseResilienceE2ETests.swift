import Foundation
@testable import Unmissable
import XCTest

/// E2E tests for database error resilience: concurrent access, reset/recovery,
/// and edge cases in the DB → scheduler pipeline.
@MainActor
final class DatabaseResilienceE2ETests: XCTestCase {
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

    // MARK: - Database Reset and Recovery

    func testDatabaseResetClearsAllDataAndRecovery() async throws {
        // Seed data
        let events = E2EEventBuilder.eventBatch(count: 5, startingMinutesFromNow: 10)
        try await env.seedEvents(events)

        let beforeReset = try await env.fetchUpcomingEvents()
        let firstEvent = try XCTUnwrap(beforeReset.first)
        XCTAssertEqual(firstEvent.title, "Batch Meeting 1")
        XCTAssertEqual(beforeReset.map(\.id).sorted(), (0 ..< 5).map { "e2e-batch-\($0)" })

        // Reset database
        try await env.databaseManager.resetDatabase()

        // All events should be gone
        let afterReset = try await env.fetchUpcomingEvents()
        XCTAssertEqual(afterReset, [])

        // Database should still be functional — can save new events
        let newEvent = E2EEventBuilder.futureEvent(
            id: "e2e-post-reset",
            title: "Post-Reset Meeting",
            minutesFromNow: 20,
        )
        try await env.seedEvents([newEvent])

        let postSave = try await env.fetchUpcomingEvents()
        let postResetEvent = try XCTUnwrap(postSave.first)
        XCTAssertEqual(postResetEvent.id, "e2e-post-reset")
    }

    // MARK: - Concurrent Database Access

    func testSequentialBatchSavesDoNotCorruptData() async throws {
        // Save 5 batches of 5 events sequentially (GRDB handles concurrency internally)
        for batchIndex in 0 ..< 5 {
            let batch = (0 ..< 5).map { eventIndex in
                E2EEventBuilder.futureEvent(
                    id: "e2e-concurrent-\(batchIndex)-\(eventIndex)",
                    title: "Batch \(batchIndex) Event \(eventIndex)",
                    minutesFromNow: 10 + batchIndex * 10 + eventIndex,
                    calendarId: "concurrent-cal-\(batchIndex)",
                )
            }
            try await env.seedEvents(batch)
        }

        // All 25 events should be saved without corruption
        let allEvents = try await env.databaseManager.fetchEvents(
            from: Date(), to: Date().addingTimeInterval(86_400),
        )
        // Verify no duplicates — all 25 events should be present with unique IDs
        let expectedIds = Set((0 ..< 5).flatMap { batch in
            (0 ..< 5).map { "e2e-concurrent-\(batch)-\($0)" }
        })
        let actualIds = Set(allEvents.map(\.id))
        XCTAssertEqual(actualIds, expectedIds, "All 25 saved events should be present with unique IDs")
    }

    func testInterleavedReadAndWriteDoNotConflict() async throws {
        let events = E2EEventBuilder.eventBatch(count: 10, startingMinutesFromNow: 10)
        try await env.seedEvents(events)

        // Interleave reads and writes sequentially
        for i in 0 ..< 5 {
            // Write
            let newEvent = E2EEventBuilder.futureEvent(
                id: "e2e-rw-\(i)",
                minutesFromNow: 60 + i * 5,
            )
            try await env.seedEvents([newEvent])

            // Read
            let fetched = try await env.fetchUpcomingEvents(limit: 100)
            XCTAssertGreaterThanOrEqual(
                fetched.count,
                10 + i,
                "Should see at least \(10 + i) events after write \(i)",
            )
        }

        // Final state should have all events
        let finalEvents = try await env.fetchUpcomingEvents(limit: 100)
        let finalIds = Set(finalEvents.map(\.id))
        let numberOfFinalEvents = finalEvents.count
        XCTAssertEqual(numberOfFinalEvents, 15, "Should have original 10 + 5 new events")
        XCTAssertEqual(finalIds.intersection(["e2e-rw-0", "e2e-rw-4"]), ["e2e-rw-0", "e2e-rw-4"])
    }

    // MARK: - Replace Events Atomicity

    func testReplaceEventsIsAtomicNoPartialState() async throws {
        let originalEvents = (0 ..< 5).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-atomic-old-\(i)",
                minutesFromNow: 20 + i * 5,
                calendarId: "atomic-cal",
            )
        }
        try await env.seedEvents(originalEvents)

        let newEvents = (0 ..< 3).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-atomic-new-\(i)",
                minutesFromNow: 25 + i * 10,
                calendarId: "atomic-cal",
            )
        }

        try await env.databaseManager.replaceEvents(for: "atomic-cal", with: newEvents)

        let afterReplace = try await env.databaseManager.fetchEvents(
            from: Date(), to: Date().addingTimeInterval(86_400),
        )

        // Should only have the new events, not a mix of old and new
        let calEventIds = Set(afterReplace.filter { $0.calendarId == "atomic-cal" }.map(\.id))
        XCTAssertEqual(calEventIds, Set(["e2e-atomic-new-0", "e2e-atomic-new-1", "e2e-atomic-new-2"]))
    }

    // MARK: - Scheduler Resilience

    func testSchedulerHandlesEmptyEventList() async {
        // Start scheduling with no events
        await env.eventScheduler.startScheduling(
            events: [], overlayManager: env.overlayManager,
        )

        XCTAssertEqual(env.eventScheduler.scheduledAlerts, [])
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
    }

    func testSchedulerHandlesStopWhileRunning() async throws {
        let events = E2EEventBuilder.eventBatch(count: 10, startingMinutesFromNow: 10)
        try await env.seedAndSchedule(events)

        XCTAssertFalse(
            env.eventScheduler.scheduledAlerts.isEmpty,
            "Should have scheduled alerts after seeding",
        )

        // Stop mid-execution
        env.eventScheduler.stopScheduling()
        XCTAssertEqual(env.eventScheduler.scheduledAlerts, [])

        // Overlay state should be clean
        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
    }

    func testSchedulerHandlesRestartWithDifferentEvents() async throws {
        let firstBatch = E2EEventBuilder.eventBatch(count: 3, startingMinutesFromNow: 10)
        try await env.seedAndSchedule(firstBatch)

        let alertIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        XCTAssertEqual(alertIds, Set(["e2e-batch-0", "e2e-batch-1", "e2e-batch-2"]))

        // Stop and restart with different events
        env.eventScheduler.stopScheduling()

        let secondBatch = (0 ..< 5).map { i in
            E2EEventBuilder.futureEvent(
                id: "e2e-restart-\(i)",
                title: "Restart Meeting \(i)",
                minutesFromNow: 50 + (i * 10),
                calendarId: "e2e-calendar",
            )
        }
        try await env.seedEvents(secondBatch)

        let allUpcoming = try await env.fetchUpcomingEvents(limit: 100)
        await env.eventScheduler.startScheduling(
            events: allUpcoming, overlayManager: env.overlayManager,
        )

        // Should have alerts for ALL events in the DB
        XCTAssertGreaterThanOrEqual(env.eventScheduler.scheduledAlerts.count, 5)
        XCTAssertTrue(env.eventScheduler.scheduledAlerts.contains { $0.event.id == "e2e-restart-0" })
    }

    // MARK: - Maintenance Lifecycle

    func testMaintenancePurgesOldEventsAndSchedulerUpdates() async throws {
        // Seed old events and recent events
        let oldEvent = Event(
            id: "e2e-maint-old",
            title: "Ancient Meeting",
            startDate: Date().addingTimeInterval(-45 * 86_400),
            endDate: Date().addingTimeInterval(-45 * 86_400 + 3600),
            calendarId: "e2e-maint-cal",
            createdAt: Date().addingTimeInterval(-45 * 86_400),
            updatedAt: Date().addingTimeInterval(-45 * 86_400),
        )
        let recentEvent = E2EEventBuilder.futureEvent(
            id: "e2e-maint-recent",
            title: "Recent Meeting",
            minutesFromNow: 30,
            calendarId: "e2e-maint-cal",
        )

        try await env.seedEvents([oldEvent, recentEvent])

        // Verify both are in DB
        let allBeforeMaint = try await env.databaseManager.fetchEvents(
            from: Date().addingTimeInterval(-90 * 86_400),
            to: Date().addingTimeInterval(86_400),
        )
        XCTAssertTrue(allBeforeMaint.contains { $0.id == "e2e-maint-old" })
        XCTAssertTrue(allBeforeMaint.contains { $0.id == "e2e-maint-recent" })

        // Run maintenance
        try await env.databaseManager.performMaintenance()

        // Old event should be purged
        let allAfterMaint = try await env.databaseManager.fetchEvents(
            from: Date().addingTimeInterval(-90 * 86_400),
            to: Date().addingTimeInterval(86_400),
        )
        XCTAssertFalse(allAfterMaint.contains { $0.id == "e2e-maint-old" })
        XCTAssertTrue(allAfterMaint.contains { $0.id == "e2e-maint-recent" })

        // Re-schedule after maintenance
        let upcoming = try await env.fetchUpcomingEvents()
        env.eventScheduler.stopScheduling()
        await env.eventScheduler.startScheduling(
            events: upcoming, overlayManager: env.overlayManager,
        )

        // Only recent event should have alert
        let alertIds = env.eventScheduler.scheduledAlerts.map(\.event.id)
        XCTAssert(alertIds.contains("e2e-maint-recent"))
        XCTAssertFalse(alertIds.contains("e2e-maint-old"))
    }

    // MARK: - Database Initialization Edge Cases

    func testFreshDatabaseCreatedSuccessfully() async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("e2e-fresh-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let freshDB = DatabaseManager(databaseURL: tempURL)
        let initialized = await freshDB.isInitialized
        let error = await freshDB.initializationError
        XCTAssertTrue(initialized)
        XCTAssertNil(error)
    }

    func testDatabaseDeleteOldEventsPreservesRecent() async throws {
        let recentEvent = E2EEventBuilder.futureEvent(
            id: "e2e-recent",
            minutesFromNow: 30,
        )
        let oldEvent = Event(
            id: "e2e-old-event",
            title: "Very Old Event",
            startDate: Date().addingTimeInterval(-60 * 86_400), // 60 days ago
            endDate: Date().addingTimeInterval(-60 * 86_400 + 3600),
            calendarId: "e2e-cal",
            createdAt: Date().addingTimeInterval(-60 * 86_400),
            updatedAt: Date().addingTimeInterval(-60 * 86_400),
        )

        try await env.seedEvents([recentEvent, oldEvent])

        // Delete events older than 30 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        try await env.databaseManager.deleteOldEvents(before: cutoff)

        let remaining = try await env.databaseManager.fetchEvents(
            from: Date().addingTimeInterval(-365 * 86_400),
            to: Date().addingTimeInterval(86_400),
        )

        let ids = Set(remaining.map(\.id))
        XCTAssert(ids.isSuperset(of: ["e2e-recent"]), "Recent event should be preserved")
        XCTAssert(ids.isDisjoint(with: ["e2e-old-event"]), "Old event should be deleted")
    }
}
