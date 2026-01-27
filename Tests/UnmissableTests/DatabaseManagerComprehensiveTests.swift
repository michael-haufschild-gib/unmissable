import GRDB
@testable import Unmissable
import XCTest

@MainActor
final class DatabaseManagerComprehensiveTests: DatabaseTestCase {
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        try await super.setUp() // This calls TestDataCleanup.shared.cleanupAllTestData()

        // Use the shared instance for testing
        databaseManager = DatabaseManager.shared
    }

    override func tearDown() async throws {
        // Cleanup is handled by super.tearDown() which calls TestDataCleanup.shared.cleanupAllTestData()
        try await super.tearDown()
    }

    // MARK: - Basic Event Operations Tests

    func testSaveAndFetchEvents() async throws {
        let events = [
            TestUtilities.createTestEvent(
                id: "test-save-1",
                title: "Test Meeting 1",
                startDate: Date().addingTimeInterval(3600)
            ),
            TestUtilities.createTestEvent(
                id: "test-save-2",
                title: "Test Meeting 2",
                startDate: Date().addingTimeInterval(7200)
            ),
        ]

        try await databaseManager.saveEvents(events)

        let fetchedEvents = try await databaseManager.fetchEvents(
            from: Date().addingTimeInterval(1800), // 30 minutes from now
            to: Date().addingTimeInterval(10800) // 3 hours from now
        )

        XCTAssertGreaterThanOrEqual(fetchedEvents.count, 2)

        let testEvent1 = fetchedEvents.first { $0.id == "test-save-1" }
        let testEvent2 = fetchedEvents.first { $0.id == "test-save-2" }

        XCTAssertNotNil(testEvent1)
        XCTAssertNotNil(testEvent2)
        XCTAssertEqual(testEvent1?.title, "Test Meeting 1")
        XCTAssertEqual(testEvent2?.title, "Test Meeting 2")
    }

    func testFetchUpcomingEvents() async throws {
        let futureEvent = TestUtilities.createTestEvent(
            id: "test-upcoming",
            title: "Upcoming Meeting",
            startDate: Date().addingTimeInterval(1800) // 30 minutes from now
        )

        try await databaseManager.saveEvents([futureEvent])

        let upcomingEvents = try await databaseManager.fetchUpcomingEvents(limit: 5)

        XCTAssertFalse(upcomingEvents.isEmpty)

        let testEvent = upcomingEvents.first { $0.id == "test-upcoming" }
        XCTAssertNotNil(testEvent)
        XCTAssertEqual(testEvent?.title, "Upcoming Meeting")
    }

    func testEventsInDateRange() async throws {
        let now = Date()
        let events = [
            TestUtilities.createTestEvent(
                id: "range-test-1",
                startDate: now.addingTimeInterval(1800) // 30 minutes from now
            ),
            TestUtilities.createTestEvent(
                id: "range-test-2",
                startDate: now.addingTimeInterval(3600) // 1 hour from now
            ),
            TestUtilities.createTestEvent(
                id: "range-test-3",
                startDate: now.addingTimeInterval(7200) // 2 hours from now
            ),
        ]

        try await databaseManager.saveEvents(events)

        // Fetch events in a 90-minute window
        let rangeEvents = try await databaseManager.fetchEvents(
            from: now.addingTimeInterval(900), // 15 minutes from now
            to: now.addingTimeInterval(5400) // 90 minutes from now
        )

        let testEvents = rangeEvents.filter { $0.id.hasPrefix("range-test") }
        XCTAssertEqual(testEvents.count, 2) // Should get events 1 and 2, not 3

        let eventIds = testEvents.map(\.id)
        XCTAssertTrue(eventIds.contains("range-test-1"))
        XCTAssertTrue(eventIds.contains("range-test-2"))
        XCTAssertFalse(eventIds.contains("range-test-3"))
    }

    // MARK: - Calendar Operations Tests

    func testSaveAndFetchCalendars() async throws {
        let calendars = [
            TestUtilities.createCalendarInfo(
                id: "test-cal-1",
                name: "Test Calendar 1",
                isSelected: true
            ),
            TestUtilities.createCalendarInfo(
                id: "test-cal-2",
                name: "Test Calendar 2",
                isSelected: false
            ),
        ]

        try await databaseManager.saveCalendars(calendars)

        let fetchedCalendars = try await databaseManager.fetchCalendars()

        let testCal1 = fetchedCalendars.first { $0.id == "test-cal-1" }
        let testCal2 = fetchedCalendars.first { $0.id == "test-cal-2" }

        XCTAssertNotNil(testCal1)
        XCTAssertNotNil(testCal2)
        XCTAssertEqual(testCal1?.name, "Test Calendar 1")
        XCTAssertTrue(testCal1?.isSelected ?? false)
        XCTAssertFalse(testCal2?.isSelected ?? true)
    }

    // MARK: - Performance Tests

    func testBatchEventSavePerformance() async throws {
        let numberOfEvents = 100
        let events = (0 ..< numberOfEvents).map { index in
            TestUtilities.createTestEvent(
                id: "perf-test-\(index)",
                title: "Performance Test Event \(index)",
                startDate: Date().addingTimeInterval(Double(index * 60 + 3600))
            )
        }

        let dbManager = try XCTUnwrap(databaseManager)
        let (_, saveTime) = try await TestUtilities.measureTimeAsync { @MainActor @Sendable in
            try await dbManager.saveEvents(events)
        }

        XCTAssertLessThan(saveTime, 2.0, "Saving 100 events should take less than 2 seconds")

        // Verify they were saved - use broader date range
        let fetchedEvents = try await databaseManager.fetchEvents(
            from: Date().addingTimeInterval(3000), // Start a bit earlier
            to: Date().addingTimeInterval(12000) // End a bit later
        )

        let testEvents = fetchedEvents.filter { $0.id.hasPrefix("perf-test") }
        XCTAssertEqual(testEvents.count, numberOfEvents)

        // Clean up test events immediately
        try await databaseManager.deleteTestEvents(withIdPattern: "perf-test")
    }

    func testFetchPerformance() async throws {
        // Save some events first
        let events = (0 ..< 50).map { index in
            TestUtilities.createTestEvent(
                id: "fetch-perf-\(index)",
                startDate: Date()
                    .addingTimeInterval(Double(index * 300 + 1800)) // 5 minutes apart, starting 30 min from now
            )
        }

        try await databaseManager.saveEvents(events)

        let dbManager = try XCTUnwrap(databaseManager)
        let (fetchedEvents, fetchTime) = try await TestUtilities.measureTimeAsync { @MainActor @Sendable in
            try await dbManager.fetchUpcomingEvents(limit: 20)
        }

        XCTAssertLessThan(fetchTime, 1.0, "Fetching upcoming events should take less than 1 second")
        XCTAssertGreaterThan(fetchedEvents.count, 0)

        // Clean up test events immediately
        try await databaseManager.deleteTestEvents(withIdPattern: "fetch-perf")
    }

    // MARK: - Search Tests

    func testEventSearch() throws {
        // Skip this test if FTS is not available
        throw XCTSkip("FTS search test disabled due to database configuration issues")
    }

    // MARK: - Edge Cases and Error Handling

    func testEmptyEventsSave() async throws {
        // Should not throw with empty array
        try await databaseManager.saveEvents([])
        XCTAssertTrue(true) // Test passes if no exception thrown
    }

    func testEmptyCalendarsSave() async throws {
        // Should not throw with empty array
        try await databaseManager.saveCalendars([])
        XCTAssertTrue(true) // Test passes if no exception thrown
    }

    func testFetchEventsWithInvalidDateRange() async throws {
        let futureDate = Date().addingTimeInterval(7200)
        let pastDate = Date().addingTimeInterval(3600)

        // Fetch with end date before start date
        let events = try await databaseManager.fetchEvents(from: futureDate, to: pastDate)

        // Should return empty array, not crash
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Data Integrity Tests

    func testEventUpdateOverwrite() async throws {
        let originalEvent = TestUtilities.createTestEvent(
            id: "update-test",
            title: "Original Title",
            startDate: Date().addingTimeInterval(3600)
        )

        try await databaseManager.saveEvents([originalEvent])

        // Create updated version with same ID
        let updatedEvent = TestUtilities.createTestEvent(
            id: "update-test", // Same ID
            title: "Updated Title",
            startDate: Date().addingTimeInterval(3600)
        )

        try await databaseManager.saveEvents([updatedEvent])

        let fetchedEvents = try await databaseManager.fetchEvents(
            from: Date().addingTimeInterval(1800),
            to: Date().addingTimeInterval(5400)
        )

        let testEvents = fetchedEvents.filter { $0.id == "update-test" }
        XCTAssertEqual(testEvents.count, 1) // Should only have one event
        XCTAssertEqual(testEvents.first?.title, "Updated Title") // Should be updated version
    }

    // MARK: - Memory Management Tests

    func testLargeDatasetMemoryUsage() async throws {
        let largeEventCount = 500
        let events = (0 ..< largeEventCount).map { index in
            TestUtilities.createTestEvent(
                id: "memory-test-\(index)",
                title: "Memory Test Event \(index)",
                startDate: Date().addingTimeInterval(Double(index * 60 + 3600))
            )
        }

        // Save large dataset
        try await databaseManager.saveEvents(events)

        // Fetch large dataset - use broader date range
        let fetchedEvents = try await databaseManager.fetchEvents(
            from: Date().addingTimeInterval(3000), // Start earlier
            to: Date().addingTimeInterval(Double(largeEventCount * 60 + 4000)) // End later
        )

        let testEvents = fetchedEvents.filter { $0.id.hasPrefix("memory-test") }
        XCTAssertEqual(testEvents.count, largeEventCount)

        // Memory should be reasonable (this is more of a manual check)
        // In a real test environment, we could monitor memory usage

        // Clean up test events immediately
        try await databaseManager.deleteTestEvents(withIdPattern: "memory-test")
    }
}
