@testable import Unmissable
import XCTest

@MainActor
final class DatabaseConcurrencyIntegrationTests: XCTestCase {
    private var db: DatabaseManager!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "unmissable-dbtest-\(UUID().uuidString)",
            )
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true,
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
                                Double(batch * 100 + i * 10 + 600),
                            ),
                            endDate: Date().addingTimeInterval(
                                Double(batch * 100 + i * 10 + 4200),
                            ),
                            calendarId: "cal-concurrent-\(batch)",
                            timezone: "UTC",
                            createdAt: Date(),
                            updatedAt: Date(),
                        )
                    }
                    try? await database.saveEvents(events)
                }
            }
        }

        // All 50 events should be present without corruption
        let allEvents = try await db.fetchEvents(
            from: Date(), to: Date().addingTimeInterval(86_400),
        )
        let expectedIds = Set((0 ..< 10).flatMap { batch in
            (0 ..< 5).map { "concurrent-\(batch)-\($0)" }
        })
        let actualIds = Set(allEvents.map(\.id))
        XCTAssertEqual(actualIds, expectedIds, "All 50 concurrent events should be saved with unique IDs")
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
                updatedAt: Date(),
            )
        }
        try await db.saveEvents(events)

        // Simultaneously read and write
        await withTaskGroup(of: Void.self) { group in
            // Readers
            for _ in 0 ..< 5 {
                group.addTask { @Sendable in
                    let fetched = try? await database.fetchUpcomingEvents(limit: 50)
                    // Verify the read returned a non-nil, non-empty result
                    let count = fetched?.count ?? 0
                    XCTAssertGreaterThanOrEqual(
                        count,
                        1,
                        "Read should succeed and return seeded events during concurrent writes",
                    )
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
                        updatedAt: Date(),
                    )
                    try? await database.saveEvents([newEvent])
                }
            }
        }

        // Final state should include all original + new events
        let finalEvents = try await db.fetchEvents(
            from: Date(), to: Date().addingTimeInterval(100_000),
        )
        XCTAssertGreaterThanOrEqual(finalEvents.count, 10, "Original events should persist")
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
            sourceProvider: .google,
        )
        let apple = CalendarInfo(
            id: "apple-cal",
            name: "Apple Personal",
            isSelected: true,
            isPrimary: false,
            sourceProvider: .apple,
        )
        try await db.saveCalendars([google, apple])

        let googleCals = try await db.fetchCalendars(
            for: .google,
        )
        let googleCal = try XCTUnwrap(googleCals.first)
        XCTAssertEqual(googleCal.id, "google-cal")

        let appleCals = try await db.fetchCalendars(for: .apple)
        let appleCal = try XCTUnwrap(appleCals.first)
        XCTAssertEqual(appleCal.id, "apple-cal")
    }
}
