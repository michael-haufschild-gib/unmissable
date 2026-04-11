import Foundation
import Testing
@testable import Unmissable

@MainActor
final class EventOverrideTests {
    private var db: DatabaseManager
    private let tempDir: URL

    /// Default calendar ID used by most tests.
    private let calId = "cal-1"

    init() throws {
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

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - CRUD

    @Test
    func saveAndFetchAlertOverride_roundtrips() async throws {
        try await db.saveAlertOverride(eventId: "event-1", calendarId: calId, minutes: 10)

        let result = try await db.fetchAlertOverride(for: "event-1", calendarId: calId)
        #expect(result == 10)
    }

    @Test
    func fetchAlertOverride_noOverride_returnsNil() async throws {
        let result = try await db.fetchAlertOverride(for: "nonexistent", calendarId: calId)
        #expect(result == nil, "Should return nil when no override exists")
    }

    @Test
    func saveAlertOverride_nilMinutes_deletesOverride() async throws {
        try await db.saveAlertOverride(eventId: "event-1", calendarId: calId, minutes: 5)
        try await db.saveAlertOverride(eventId: "event-1", calendarId: calId, minutes: nil)

        let result = try await db.fetchAlertOverride(for: "event-1", calendarId: calId)
        #expect(result == nil, "Override should be deleted when nil is saved")
    }

    @Test
    func saveAlertOverride_updatesExistingOverride() async throws {
        try await db.saveAlertOverride(eventId: "event-1", calendarId: calId, minutes: 5)
        try await db.saveAlertOverride(eventId: "event-1", calendarId: calId, minutes: 15)

        let result = try await db.fetchAlertOverride(for: "event-1", calendarId: calId)
        #expect(result == 15, "Override should be updated to new value")
    }

    @Test
    func saveAlertOverride_zeroMinutes_persistsAsNoAlert() async throws {
        try await db.saveAlertOverride(eventId: "event-1", calendarId: calId, minutes: 0)

        let result = try await db.fetchAlertOverride(for: "event-1", calendarId: calId)
        #expect(result == 0, "Zero should persist as 'no alert'")
    }

    @Test
    func fetchAllAlertOverrides_returnsAllOverrides() async throws {
        try await db.saveAlertOverride(eventId: "event-1", calendarId: calId, minutes: 5)
        try await db.saveAlertOverride(eventId: "event-2", calendarId: calId, minutes: 10)
        try await db.saveAlertOverride(eventId: "event-3", calendarId: calId, minutes: 0)

        let overrides = try await db.fetchAllAlertOverrides()
        let key1 = EventOverride.compoundKey(eventId: "event-1", calendarId: calId)
        let key2 = EventOverride.compoundKey(eventId: "event-2", calendarId: calId)
        let key3 = EventOverride.compoundKey(eventId: "event-3", calendarId: calId)
        #expect(overrides[key1] == 5)
        #expect(overrides[key2] == 10)
        #expect(overrides[key3] == 0)
    }

    @Test
    func fetchAllAlertOverrides_emptyDatabase_returnsEmptyDict() async throws {
        let overrides = try await db.fetchAllAlertOverrides()
        #expect(overrides.isEmpty, "Empty database should return empty dictionary")
    }

    // MARK: - Compound Key Collision

    @Test
    func compoundKey_doesNotCollideOnUnderscoreAmbiguity() {
        // Google recurring event instance IDs use "<baseId>_<ISO timestamp>" format,
        // so underscores appear in real event IDs. A naive "eventId_calendarId" join
        // would collide with ("eventId", "suffix_calendarId"). The compound key must
        // use a separator that cannot appear in either ID.
        let a = EventOverride.compoundKey(
            eventId: "event_20260411T100000Z", calendarId: "cal1",
        )
        let b = EventOverride.compoundKey(
            eventId: "event", calendarId: "20260411T100000Z_cal1",
        )
        #expect(a != b, "Compound keys must not collide on underscore boundaries")
    }

    // MARK: - Validation

    @Test
    func saveAlertOverride_negativeMinutes_clampedToZero() async throws {
        try await db.saveAlertOverride(eventId: "event-1", calendarId: calId, minutes: -5)

        let result = try await db.fetchAlertOverride(for: "event-1", calendarId: calId)
        #expect(result == 0, "Negative minutes should be clamped to 0")
    }

    @Test
    func saveAlertOverride_excessiveMinutes_clampedToMax() async throws {
        try await db.saveAlertOverride(eventId: "event-1", calendarId: calId, minutes: 120)

        let result = try await db.fetchAlertOverride(for: "event-1", calendarId: calId)
        #expect(result == 60, "Minutes exceeding 60 should be clamped to 60")
    }

    // MARK: - Override Survives Sync

    @Test
    func overrideSurvivesReplaceEvents() async throws {
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
        try await db.saveAlertOverride(eventId: "sync-event-1", calendarId: calendarId, minutes: 10)

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
        let override = try await db.fetchAlertOverride(for: "sync-event-1", calendarId: calendarId)
        #expect(
            override == 10,
            "Override must survive replaceEvents since it's in a separate table",
        )
    }

    @Test
    func overrideSurvivesReplaceEvents_eventRemovedFromSync() async throws {
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
        try await db.saveAlertOverride(eventId: "removed-event", calendarId: calendarId, minutes: 5)

        // Sync removes this event (empty replacement)
        try await db.replaceEvents(for: calendarId, with: [])

        // Override still exists (orphaned) — cleaned up by maintenance
        let override = try await db.fetchAlertOverride(for: "removed-event", calendarId: calendarId)
        #expect(
            override == 5,
            "Orphaned override persists until maintenance cleanup",
        )
    }

    // MARK: - Maintenance Cleanup

    @Test
    func performMaintenance_cleansOrphanedOverrides() async throws {
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
        try await db.saveAlertOverride(eventId: "living-event", calendarId: "cal-1", minutes: 10)
        try await db.saveAlertOverride(eventId: "dead-event", calendarId: "cal-1", minutes: 5)

        try await db.performMaintenance()

        let livingOverride = try await db.fetchAlertOverride(for: "living-event", calendarId: "cal-1")
        #expect(
            livingOverride == 10,
            "Override for existing event should survive maintenance",
        )

        let deadOverride = try await db.fetchAlertOverride(for: "dead-event", calendarId: "cal-1")
        #expect(
            deadOverride == nil,
            "Orphaned override should be cleaned up by maintenance",
        )
    }
}
