@testable import Unmissable
import XCTest

@MainActor
final class DatabaseManagerIntegrationTests: XCTestCase {
    private var db: DatabaseManager!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "unmissable-dbtest-\(UUID().uuidString)"
            )
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        let dbURL = tempDir.appendingPathComponent("test.db")
        db = DatabaseManager(databaseURL: dbURL)
    }

    override func tearDown() async throws {
        db = nil
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
        try await super.tearDown()
    }

    // MARK: - Migration

    func testMigrationChainRunsWithoutError() async {
        let error = await db.initializationError
        XCTAssertNil(error, "Fresh DB should initialize without error")
    }

    // MARK: - Event Roundtrip

    func testRoundtripSaveFetchEvents() async throws {
        let start = Date().addingTimeInterval(600)
        let end = start.addingTimeInterval(3600)
        let event = Event(
            id: "roundtrip-1",
            title: "Roundtrip Meeting",
            startDate: start,
            endDate: end,
            organizer: "org@test.com",
            isAllDay: false,
            calendarId: "cal-1",
            timezone: "America/New_York",
            links: [],
            provider: .zoom,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await db.saveEvents([event])

        let fetched = try await db.fetchUpcomingEvents(limit: 50)
        let match = try XCTUnwrap(
            fetched.first { $0.id == "roundtrip-1" }
        )
        XCTAssertEqual(match.title, "Roundtrip Meeting")
        XCTAssertEqual(match.organizer, "org@test.com")
        XCTAssertEqual(match.calendarId, "cal-1")
        XCTAssertEqual(match.timezone, "America/New_York")
        XCTAssertEqual(match.provider, .zoom)
        XCTAssertFalse(match.isAllDay)
    }

    // MARK: - Replace Events

    func testReplaceEventsAtomicallyReplacesCalendarEvents()
        async throws
    {
        let start = Date().addingTimeInterval(600)
        let end = start.addingTimeInterval(3600)
        let calendarId = "cal-replace"

        let oldEvent = Event(
            id: "old-1",
            title: "Old Meeting",
            startDate: start,
            endDate: end,
            calendarId: calendarId,
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([oldEvent])

        let newEvent = Event(
            id: "new-1",
            title: "New Meeting",
            startDate: start,
            endDate: end,
            calendarId: calendarId,
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.replaceEvents(
            for: calendarId,
            with: [newEvent]
        )

        let fetched = try await db.fetchUpcomingEvents(limit: 50)
        let ids = fetched.map(\.id)
        XCTAssertFalse(ids.contains("old-1"))

        let match = try XCTUnwrap(
            fetched.first { $0.id == "new-1" }
        )
        XCTAssertEqual(match.title, "New Meeting")
    }

    // MARK: - Delete Events for Calendar

    func testDeleteEventsForCalendarRemovesOnlyTargetCalendar()
        async throws
    {
        let start = Date().addingTimeInterval(600)
        let end = start.addingTimeInterval(3600)

        let keepEvent = Event(
            id: "keep-1",
            title: "Keep Me",
            startDate: start,
            endDate: end,
            calendarId: "cal-keep",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        let deleteEvent = Event(
            id: "delete-1",
            title: "Delete Me",
            startDate: start,
            endDate: end,
            calendarId: "cal-delete",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([keepEvent, deleteEvent])

        try await db.deleteEventsForCalendar("cal-delete")

        let fetched = try await db.fetchUpcomingEvents(limit: 50)
        let ids = fetched.map(\.id)
        XCTAssertEqual(ids, ["keep-1"])
    }

    // MARK: - Fetch Upcoming Events

    func testFetchUpcomingEventsReturnsOrderedAndLimited()
        async throws
    {
        let now = Date()
        var events: [Event] = []
        for i in 1 ... 5 {
            events.append(Event(
                id: "upcoming-\(i)",
                title: "Event \(i)",
                startDate: now.addingTimeInterval(
                    Double(i) * 600
                ),
                endDate: now.addingTimeInterval(
                    Double(i) * 600 + 3600
                ),
                calendarId: "cal-upcoming",
                timezone: "UTC",
                createdAt: Date(),
                updatedAt: Date()
            ))
        }
        try await db.saveEvents(events)

        let fetched = try await db.fetchUpcomingEvents(limit: 3)
        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(fetched[0].id, "upcoming-1")
        XCTAssertEqual(fetched[1].id, "upcoming-2")
        XCTAssertEqual(fetched[2].id, "upcoming-3")
    }

    // MARK: - Fetch Started Meetings

    func testFetchStartedMeetingsReturnsInProgressEvents()
        async throws
    {
        let now = Date()
        let inProgress = Event(
            id: "in-progress-1",
            title: "Happening Now",
            startDate: now.addingTimeInterval(-1800),
            endDate: now.addingTimeInterval(1800),
            calendarId: "cal-started",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        let future = Event(
            id: "future-1",
            title: "Future Event",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(7200),
            calendarId: "cal-started",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        let past = Event(
            id: "past-1",
            title: "Already Done",
            startDate: now.addingTimeInterval(-7200),
            endDate: now.addingTimeInterval(-3600),
            calendarId: "cal-started",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([inProgress, future, past])

        let started = try await db.fetchStartedMeetings(limit: 10)
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started[0].id, "in-progress-1")
        XCTAssertEqual(started[0].title, "Happening Now")
    }

    // MARK: - Search Events (FTS)

    func testSearchEventsReturnsFTSMatches() async throws {
        let start = Date().addingTimeInterval(600)
        let end = start.addingTimeInterval(3600)

        let matchEvent = Event(
            id: "search-match",
            title: "Quarterly Budget Review",
            startDate: start,
            endDate: end,
            organizer: "finance@corp.com",
            calendarId: "cal-search",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        let noMatchEvent = Event(
            id: "search-nomatch",
            title: "Daily Standup",
            startDate: start,
            endDate: end,
            calendarId: "cal-search",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([matchEvent, noMatchEvent])

        let results = try await db.searchEvents(query: "Budget")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "search-match")
    }

    // MARK: - Perform Maintenance

    func testPerformMaintenanceCleansUpOldEvents() async throws {
        let now = Date()
        let oldEnd = now.addingTimeInterval(-40 * 86_400)
        let oldEvent = Event(
            id: "old-event",
            title: "Ancient Meeting",
            startDate: oldEnd.addingTimeInterval(-3600),
            endDate: oldEnd,
            calendarId: "cal-maint",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        let recentEvent = Event(
            id: "recent-event",
            title: "Recent Meeting",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(4200),
            calendarId: "cal-maint",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([oldEvent, recentEvent])

        try await db.performMaintenance()

        let remaining = try await db.fetchEvents(
            from: Date.distantPast,
            to: Date.distantFuture
        )
        let ids = remaining.map(\.id)
        XCTAssertFalse(ids.contains("old-event"))

        let recent = try XCTUnwrap(
            remaining.first { $0.id == "recent-event" }
        )
        XCTAssertEqual(recent.title, "Recent Meeting")
    }

    // MARK: - Upsert and Edge Cases

    func testSavingExistingEventUpdatesInPlace() async throws {
        let start = Date().addingTimeInterval(600)
        let end = start.addingTimeInterval(3600)

        let original = Event(
            id: "upsert-1",
            title: "Original Title",
            startDate: start,
            endDate: end,
            calendarId: "cal-upsert",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([original])

        // Save again with updated title
        let updated = Event(
            id: "upsert-1",
            title: "Updated Title",
            startDate: start,
            endDate: end,
            calendarId: "cal-upsert",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([updated])

        let fetched = try await db.fetchUpcomingEvents(limit: 50)
        let matches = fetched.filter { $0.id == "upsert-1" }
        XCTAssertEqual(matches.count, 1, "Should not create duplicate entries")
        XCTAssertEqual(matches.first?.title, "Updated Title", "Title should be updated")
    }

    func testSearchEventsWithSpecialCharacters() async throws {
        let event = Event(
            id: "special-search",
            title: "O'Brien's & Co. Meeting (Q1/Q2)",
            startDate: Date().addingTimeInterval(600),
            endDate: Date().addingTimeInterval(4200),
            calendarId: "cal-search-special",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([event])

        let results = try await db.searchEvents(query: "O'Brien")
        XCTAssertEqual(results.count, 1, "FTS should handle apostrophes")
    }

    func testSearchEventsWithEmptyQuery() async throws {
        let event = Event(
            id: "empty-query",
            title: "Findable Meeting",
            startDate: Date().addingTimeInterval(600),
            endDate: Date().addingTimeInterval(4200),
            calendarId: "cal-empty-q",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([event])

        let results = try await db.searchEvents(query: "")
        // Empty query should return empty results or all results depending on implementation
        // The important thing is it doesn't crash
        XCTAssertNotNil(results)
    }

    func testFetchUpcomingEventsWithZeroLimit() async throws {
        let event = Event(
            id: "zero-limit",
            title: "Test",
            startDate: Date().addingTimeInterval(600),
            endDate: Date().addingTimeInterval(4200),
            calendarId: "cal-zero",
            timezone: "UTC",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([event])

        let fetched = try await db.fetchUpcomingEvents(limit: 0)
        XCTAssertTrue(fetched.isEmpty, "Zero limit should return empty array")
    }

    // MARK: - Calendar Roundtrip

    func testSaveAndFetchCalendarsRoundtrip() async throws {
        let cal1 = CalendarInfo(
            id: "cal-rt-1",
            name: "Work",
            isSelected: true,
            isPrimary: true,
            colorHex: "#0000ff"
        )
        let cal2 = CalendarInfo(
            id: "cal-rt-2",
            name: "Personal",
            isSelected: false,
            isPrimary: false,
            colorHex: "#ff0000"
        )
        try await db.saveCalendars([cal1, cal2])

        let fetched = try await db.fetchCalendars()
        XCTAssertEqual(fetched.count, 2)

        let primary = try XCTUnwrap(
            fetched.first { $0.id == "cal-rt-1" }
        )
        XCTAssertEqual(primary.name, "Work")
        XCTAssertTrue(primary.isPrimary)
        XCTAssertTrue(primary.isSelected)

        let personal = try XCTUnwrap(
            fetched.first { $0.id == "cal-rt-2" }
        )
        XCTAssertEqual(personal.name, "Personal")
        XCTAssertFalse(personal.isPrimary)
    }

    // MARK: - Provider-Scoped Deletion

    func testDeleteCalendarsForProvider_removesOnlyTargetProvider()
        async throws
    {
        let googleCal = CalendarInfo(
            id: "prov-del-google",
            name: "Google Cal",
            isSelected: true,
            sourceProvider: .google
        )
        let appleCal = CalendarInfo(
            id: "prov-del-apple",
            name: "Apple Cal",
            isSelected: true,
            sourceProvider: .apple
        )
        try await db.saveCalendars([googleCal, appleCal])

        try await db.deleteCalendarsForProvider(.google)

        let remaining = try await db.fetchCalendars()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "prov-del-apple")
    }

    func testDeleteEventsForProvider_removesOnlyTargetProviderEvents()
        async throws
    {
        let googleCal = CalendarInfo(
            id: "evt-del-google-cal",
            name: "Google",
            isSelected: true,
            sourceProvider: .google
        )
        let appleCal = CalendarInfo(
            id: "evt-del-apple-cal",
            name: "Apple",
            isSelected: true,
            sourceProvider: .apple
        )
        try await db.saveCalendars([googleCal, appleCal])

        let start = Date().addingTimeInterval(600)
        let end = start.addingTimeInterval(3600)
        let googleEvent = Event(
            id: "evt-del-google",
            title: "Google Event",
            startDate: start,
            endDate: end,
            calendarId: "evt-del-google-cal",
            createdAt: Date(),
            updatedAt: Date()
        )
        let appleEvent = Event(
            id: "evt-del-apple",
            title: "Apple Event",
            startDate: start,
            endDate: end,
            calendarId: "evt-del-apple-cal",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([googleEvent, appleEvent])

        try await db.deleteEventsForProvider(.google)

        let remaining = try await db.fetchUpcomingEvents(limit: 50)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "evt-del-apple")
    }

    func testDeleteAllDataForProvider_removesCalendarsAndEvents()
        async throws
    {
        let cal = CalendarInfo(
            id: "all-del-cal",
            name: "Delete All",
            isSelected: true,
            sourceProvider: .google
        )
        try await db.saveCalendars([cal])

        let event = Event(
            id: "all-del-event",
            title: "Delete All Event",
            startDate: Date().addingTimeInterval(600),
            endDate: Date().addingTimeInterval(4200),
            calendarId: "all-del-cal",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveEvents([event])

        try await db.deleteAllDataForProvider(.google)

        let calendars = try await db.fetchCalendars(for: .google)
        let events = try await db.fetchUpcomingEvents(limit: 50)
        XCTAssertTrue(calendars.isEmpty, "All Google calendars should be deleted")
        XCTAssertTrue(
            events.filter { $0.calendarId == "all-del-cal" }.isEmpty,
            "All events for Google calendars should be deleted"
        )
    }

    // MARK: - Concurrent Write Stress

    func testConcurrentWritesDoNotCorruptData() async throws {
        // Capture db reference for Sendable closure
        let database = try XCTUnwrap(db)

        // Launch 10 concurrent write tasks, each writing 5 events
        await withTaskGroup(of: Void.self) { group in
            for batch in 0 ..< 10 {
                group.addTask { @Sendable in
                    let events = (0 ..< 5).map { i in
                        Event(
                            id: "concurrent-\(batch)-\(i)",
                            title: "Batch \(batch) Event \(i)",
                            startDate: Date().addingTimeInterval(
                                Double(batch * 100 + i * 10 + 600)
                            ),
                            endDate: Date().addingTimeInterval(
                                Double(batch * 100 + i * 10 + 4200)
                            ),
                            calendarId: "cal-concurrent-\(batch)",
                            timezone: "UTC",
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                    }
                    try? await database.saveEvents(events)
                }
            }
        }

        // All 50 events should be present without corruption
        let allEvents = try await db.fetchEvents(
            from: Date(), to: Date().addingTimeInterval(86_400)
        )
        XCTAssertEqual(allEvents.count, 50, "All 50 concurrent events should be saved")

        let uniqueIds = Set(allEvents.map(\.id))
        XCTAssertEqual(uniqueIds.count, 50, "All event IDs should be unique")
    }

    func testConcurrentReadsDuringWrite() async throws {
        // Capture db reference for Sendable closures
        let database = try XCTUnwrap(db)

        // Pre-seed 10 events
        let events = (0 ..< 10).map { i in
            Event(
                id: "read-during-write-\(i)",
                title: "Event \(i)",
                startDate: Date().addingTimeInterval(Double(i * 600 + 600)),
                endDate: Date().addingTimeInterval(Double(i * 600 + 4200)),
                calendarId: "cal-rdw",
                timezone: "UTC",
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        try await db.saveEvents(events)

        // Simultaneously read and write
        await withTaskGroup(of: Void.self) { group in
            // Readers
            for _ in 0 ..< 5 {
                group.addTask { @Sendable in
                    let fetched = try? await database.fetchUpcomingEvents(limit: 50)
                    // Should not crash and should return consistent data
                    XCTAssertNotNil(fetched, "Read should succeed during concurrent writes")
                }
            }
            // Writers
            for i in 0 ..< 5 {
                group.addTask { @Sendable in
                    let newEvent = Event(
                        id: "concurrent-new-\(i)",
                        title: "New \(i)",
                        startDate: Date().addingTimeInterval(Double(i * 100 + 7000)),
                        endDate: Date().addingTimeInterval(Double(i * 100 + 10_600)),
                        calendarId: "cal-rdw",
                        timezone: "UTC",
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    try? await database.saveEvents([newEvent])
                }
            }
        }

        // Final state should include all original + new events
        let final_ = try await db.fetchEvents(
            from: Date(), to: Date().addingTimeInterval(100_000)
        )
        XCTAssertGreaterThanOrEqual(final_.count, 10, "Original events should persist")
    }

    // MARK: - Fetch Calendars by Provider

    func testFetchCalendarsForProviderFiltersCorrectly()
        async throws
    {
        let google = CalendarInfo(
            id: "google-cal",
            name: "Google Work",
            isSelected: true,
            isPrimary: true,
            sourceProvider: .google
        )
        let apple = CalendarInfo(
            id: "apple-cal",
            name: "Apple Personal",
            isSelected: true,
            isPrimary: false,
            sourceProvider: .apple
        )
        try await db.saveCalendars([google, apple])

        let googleCals = try await db.fetchCalendars(
            for: .google
        )
        XCTAssertEqual(googleCals.count, 1)
        XCTAssertEqual(googleCals[0].id, "google-cal")

        let appleCals = try await db.fetchCalendars(for: .apple)
        XCTAssertEqual(appleCals.count, 1)
        XCTAssertEqual(appleCals[0].id, "apple-cal")
    }
}
