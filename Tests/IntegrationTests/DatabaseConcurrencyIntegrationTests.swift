import Foundation
import Testing
@testable import Unmissable

@MainActor
struct DatabaseConcurrencyIntegrationTests {
    private let db: DatabaseManager
    /// Retains the temp directory until the struct is deallocated, then removes it.
    private let tempDir: TemporaryDirectory

    init() throws {
        tempDir = try TemporaryDirectory(prefix: "unmissable-dbtest")
        let dbURL = tempDir.url.appendingPathComponent("test.db")
        db = DatabaseManager(databaseURL: dbURL)
    }

    // MARK: - Concurrent Write Stress

    @Test
    func concurrentWritesDoNotCorruptData() async throws {
        // Capture db reference for Sendable closure
        let database = db

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
        #expect(actualIds == expectedIds, "All 50 concurrent events should be saved with unique IDs")
    }

    @Test
    func concurrentReadsDuringWrite() async throws {
        // Capture db reference for Sendable closures
        let database = db

        // Pre-seed 10 events
        let now = Date()
        let events: [Event] = (0 ..< 10).map { i in
            let offset = Double(i * 600 + 600)
            return Event(
                id: "read-during-write-\(i)",
                title: "Event \(i)",
                startDate: now.addingTimeInterval(offset),
                endDate: now.addingTimeInterval(offset + 3600),
                calendarId: "cal-rdw",
                timezone: "UTC",
                createdAt: now,
                updatedAt: now,
            )
        }
        try await db.saveEvents(events)

        // Launch concurrent writers in a fire-and-forget group
        async let writesDone: Void = withTaskGroup(of: Void.self) { group in
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

        // Launch concurrent readers, collecting counts to assert outside the group
        let readCounts = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0 ..< 5 {
                group.addTask { @Sendable in
                    let fetched = try? await database.fetchUpcomingEvents(limit: 50)
                    return fetched?.count ?? 0
                }
            }
            var counts: [Int] = []
            for await count in group {
                counts.append(count)
            }
            return counts
        }

        await writesDone

        // Assert read results outside the task group
        for count in readCounts {
            #expect(
                count >= 1,
                "Read should succeed and return seeded events during concurrent writes",
            )
        }

        // Final state should include all original + new events
        let finalEvents = try await db.fetchEvents(
            from: Date(), to: Date().addingTimeInterval(100_000),
        )
        #expect(
            finalEvents.count >= 11,
            "Original events should persist and at least one concurrent write should succeed",
        )
    }

    // MARK: - Fetch Calendars by Provider

    @Test
    func fetchCalendarsForProviderFiltersCorrectly()
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
        #expect(googleCals.map(\.id) == ["google-cal"], "Should return exactly one Google calendar")

        let appleCals = try await db.fetchCalendars(for: .apple)
        #expect(appleCals.map(\.id) == ["apple-cal"], "Should return exactly one Apple calendar")
    }
}
