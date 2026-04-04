@testable import Unmissable
import XCTest

@MainActor
final class EventOverrideTests: XCTestCase {
    private var db: DatabaseManager!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "unmissable-override-test-\(UUID().uuidString)",
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
            try FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
        try await super.tearDown()
    }

    // MARK: - CRUD

    func testSaveAndFetchAlertOverride_roundtrips() async throws {
        try await db.saveAlertOverride(eventId: "event-1", minutes: 10)

        let result = try await db.fetchAlertOverride(for: "event-1")
        XCTAssertEqual(result, 10)
    }

    func testFetchAlertOverride_noOverride_returnsNil() async throws {
        let result = try await db.fetchAlertOverride(for: "nonexistent")
        XCTAssertNil(result, "Should return nil when no override exists")
    }

    func testSaveAlertOverride_nilMinutes_deletesOverride() async throws {
        try await db.saveAlertOverride(eventId: "event-1", minutes: 5)
        try await db.saveAlertOverride(eventId: "event-1", minutes: nil)

        let result = try await db.fetchAlertOverride(for: "event-1")
        XCTAssertNil(result, "Override should be deleted when nil is saved")
    }

    func testSaveAlertOverride_updatesExistingOverride() async throws {
        try await db.saveAlertOverride(eventId: "event-1", minutes: 5)
        try await db.saveAlertOverride(eventId: "event-1", minutes: 15)

        let result = try await db.fetchAlertOverride(for: "event-1")
        XCTAssertEqual(result, 15, "Override should be updated to new value")
    }

    func testSaveAlertOverride_zeroMinutes_persistsAsNoAlert() async throws {
        try await db.saveAlertOverride(eventId: "event-1", minutes: 0)

        let result = try await db.fetchAlertOverride(for: "event-1")
        XCTAssertEqual(result, 0, "Zero should persist as 'no alert'")
    }

    func testFetchAllAlertOverrides_returnsAllOverrides() async throws {
        try await db.saveAlertOverride(eventId: "event-1", minutes: 5)
        try await db.saveAlertOverride(eventId: "event-2", minutes: 10)
        try await db.saveAlertOverride(eventId: "event-3", minutes: 0)

        let overrides = try await db.fetchAllAlertOverrides()
        XCTAssertEqual(overrides["event-1"], 5)
        XCTAssertEqual(overrides["event-2"], 10)
        XCTAssertEqual(overrides["event-3"], 0)
        // All three overrides are present (verified by individual key checks above)
    }

    func testFetchAllAlertOverrides_emptyDatabase_returnsEmptyDict() async throws {
        let overrides = try await db.fetchAllAlertOverrides()
        XCTAssertTrue(overrides.isEmpty, "Empty database should return empty dictionary")
    }

    // MARK: - Validation

    func testSaveAlertOverride_negativeMinutes_clampedToZero() async throws {
        try await db.saveAlertOverride(eventId: "event-1", minutes: -5)

        let result = try await db.fetchAlertOverride(for: "event-1")
        XCTAssertEqual(result, 0, "Negative minutes should be clamped to 0")
    }

    func testSaveAlertOverride_excessiveMinutes_clampedToMax() async throws {
        try await db.saveAlertOverride(eventId: "event-1", minutes: 120)

        let result = try await db.fetchAlertOverride(for: "event-1")
        XCTAssertEqual(result, 60, "Minutes exceeding 60 should be clamped to 60")
    }

    // MARK: - Override Survives Sync

    func testOverrideSurvivesReplaceEvents() async throws {
        let start = Date().addingTimeInterval(600)
        let end = start.addingTimeInterval(3600)
        let calendarId = "cal-sync"

        let event = Event(
            id: "sync-event-1",
            title: "Original Meeting",
            startDate: start,
            endDate: end,
            calendarId: calendarId,
            timezone: "UTC",
        )
        try await db.saveEvents([event])
        try await db.saveAlertOverride(eventId: "sync-event-1", minutes: 10)

        // Simulate sync: replaceEvents does full delete+insert for the calendar
        let replacementEvent = Event(
            id: "sync-event-1",
            title: "Updated Meeting",
            startDate: start,
            endDate: end,
            calendarId: calendarId,
            timezone: "UTC",
        )
        try await db.replaceEvents(for: calendarId, with: [replacementEvent])

        // Override should survive because it's in a separate table
        let override = try await db.fetchAlertOverride(for: "sync-event-1")
        XCTAssertEqual(
            override,
            10,
            "Override must survive replaceEvents since it's in a separate table",
        )
    }

    func testOverrideSurvivesReplaceEvents_eventRemovedFromSync() async throws {
        let start = Date().addingTimeInterval(600)
        let end = start.addingTimeInterval(3600)
        let calendarId = "cal-sync"

        let event = Event(
            id: "removed-event",
            title: "Meeting",
            startDate: start,
            endDate: end,
            calendarId: calendarId,
            timezone: "UTC",
        )
        try await db.saveEvents([event])
        try await db.saveAlertOverride(eventId: "removed-event", minutes: 5)

        // Sync removes this event (empty replacement)
        try await db.replaceEvents(for: calendarId, with: [])

        // Override still exists (orphaned) — cleaned up by maintenance
        let override = try await db.fetchAlertOverride(for: "removed-event")
        XCTAssertEqual(
            override,
            5,
            "Orphaned override persists until maintenance cleanup",
        )
    }

    // MARK: - Maintenance Cleanup

    func testPerformMaintenance_cleansOrphanedOverrides() async throws {
        let start = Date().addingTimeInterval(600)
        let end = start.addingTimeInterval(3600)

        let event = Event(
            id: "living-event",
            title: "Active Meeting",
            startDate: start,
            endDate: end,
            calendarId: "cal-1",
            timezone: "UTC",
        )
        try await db.saveEvents([event])

        // Create overrides for both a living and an orphaned event
        try await db.saveAlertOverride(eventId: "living-event", minutes: 10)
        try await db.saveAlertOverride(eventId: "dead-event", minutes: 5)

        try await db.performMaintenance()

        let livingOverride = try await db.fetchAlertOverride(for: "living-event")
        XCTAssertEqual(
            livingOverride,
            10,
            "Override for existing event should survive maintenance",
        )

        let deadOverride = try await db.fetchAlertOverride(for: "dead-event")
        XCTAssertNil(
            deadOverride,
            "Orphaned override should be cleaned up by maintenance",
        )
    }
}
