import Foundation
import GRDB

// MARK: - Database Migrations

extension DatabaseManager {
    /// All database schema migrations, applied sequentially.
    static let migrator: DatabaseMigrator = buildMigrator()

    private static func buildMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
        #endif

        registerV1CreateTables(&migrator)
        registerV2EventDetails(&migrator)
        registerV3Attachments(&migrator)
        registerV4SourceProvider(&migrator)
        registerV5DropLegacy(&migrator)
        registerV6EventOverrides(&migrator)
        registerV7CalendarAlertMode(&migrator)
        registerV8CompositeEventPK(&migrator)

        return migrator
    }

    private static func registerV1CreateTables(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1-createTables") { db in
            try db.create(table: Event.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("startDate", .datetime).notNull()
                t.column("endDate", .datetime).notNull()
                t.column("organizer", .text)
                t.column("isAllDay", .boolean).notNull().defaults(to: false)
                t.column("calendarId", .text).notNull()
                t.column("timezone", .text).notNull()
                t.column("links", .text).notNull().defaults(to: "[]")
                t.column("provider", .text)
                t.column("snoozeUntil", .datetime)
                t.column("autoJoinEnabled", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_events_startDate",
                on: Event.databaseTableName,
                columns: ["startDate"],
                ifNotExists: true,
            )
            try db.create(
                index: "idx_events_calendarId",
                on: Event.databaseTableName,
                columns: ["calendarId"],
                ifNotExists: true,
            )

            try db.create(table: CalendarInfo.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("isSelected", .boolean).notNull().defaults(to: false)
                t.column("isPrimary", .boolean).notNull().defaults(to: false)
                t.column("colorHex", .text)
                t.column("lastSyncAt", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // FTS for event search
            let ftsExists = try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name='events_fts'",
            ) ?? false
            if !ftsExists {
                try db.create(virtualTable: "events_fts", using: FTS5()) { t in
                    t.synchronize(withTable: Event.databaseTableName)
                    t.column("title")
                    t.column("organizer")
                }
            }
        }
    }

    private static func registerV2EventDetails(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2-eventDetails") { db in
            let columns = try Set(db.columns(in: Event.databaseTableName).map(\.name))
            let missing = ["description", "location", "attendees"].filter { !columns.contains($0) }
            guard !missing.isEmpty else { return }
            for column in missing {
                try db.alter(table: Event.databaseTableName) { t in
                    switch column {
                    case "description":
                        t.add(column: "description", .text)
                    case "location":
                        t.add(column: "location", .text)
                    case "attendees":
                        t.add(column: "attendees", .text).notNull().defaults(to: "[]")
                    default:
                        break
                    }
                }
            }
        }
    }

    private static func registerV3Attachments(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3-attachments") { db in
            let columns = try db.columns(in: Event.databaseTableName).map(\.name)
            if !columns.contains("attachments") {
                try db.alter(table: Event.databaseTableName) { t in
                    t.add(column: "attachments", .text).notNull().defaults(to: "[]")
                }
            }
        }
    }

    private static func registerV4SourceProvider(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4-sourceProvider") { db in
            let columns = try db.columns(in: CalendarInfo.databaseTableName).map(\.name)
            if !columns.contains("sourceProvider") {
                try db.alter(table: CalendarInfo.databaseTableName) { t in
                    t.add(column: "sourceProvider", .text).notNull().defaults(to: "google")
                }
            }
        }
    }

    private static func registerV5DropLegacy(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5-dropLegacySchemaVersion") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS schema_version")
        }
    }

    private static func registerV6EventOverrides(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v6-eventOverrides") { db in
            try db.create(table: EventOverride.databaseTableName, ifNotExists: true) { t in
                t.column("eventId", .text).primaryKey()
                t.column("alertMinutes", .integer).notNull()
            }
        }
    }

    private static func registerV7CalendarAlertMode(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7-calendarAlertMode") { db in
            let columns = try db.columns(in: CalendarInfo.databaseTableName).map(\.name)
            if !columns.contains("alertMode") {
                try db.alter(table: CalendarInfo.databaseTableName) { t in
                    t.add(column: "alertMode", .text).notNull().defaults(to: "overlay")
                }
            }
        }
    }

    private static func registerV8CompositeEventPK(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v8-compositeEventPK") { db in
            // -- Events: migrate from single PK (id) to composite PK (id, calendarId) --
            try db.rename(table: Event.databaseTableName, to: "events_old")
            // FTS5 content-sync tables reference the source table by name;
            // drop before recreating the source table.
            try db.execute(sql: "DROP TABLE IF EXISTS events_fts")

            try db.create(table: Event.databaseTableName) { t in
                t.primaryKey {
                    t.column("id", .text)
                    t.column("calendarId", .text)
                }
                t.column("title", .text).notNull()
                t.column("startDate", .datetime).notNull()
                t.column("endDate", .datetime).notNull()
                t.column("organizer", .text)
                t.column("description", .text)
                t.column("location", .text)
                t.column("attendees", .text).notNull().defaults(to: "[]")
                t.column("attachments", .text).notNull().defaults(to: "[]")
                t.column("isAllDay", .boolean).notNull().defaults(to: false)
                t.column("timezone", .text).notNull()
                t.column("links", .text).notNull().defaults(to: "[]")
                t.column("provider", .text)
                t.column("snoozeUntil", .datetime)
                t.column("autoJoinEnabled", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Copy data. If duplicate (id) rows exist from the old schema,
            // INSERT OR IGNORE keeps only the first (ordered by updatedAt DESC).
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO \(Event.databaseTableName)
                SELECT id, calendarId, title, startDate, endDate, organizer,
                       description, location, attendees, attachments,
                       isAllDay, timezone, links, provider,
                       snoozeUntil, autoJoinEnabled, createdAt, updatedAt
                FROM events_old
                ORDER BY updatedAt DESC
                """,
            )
            try db.drop(table: "events_old")

            try db.create(
                index: "idx_events_startDate",
                on: Event.databaseTableName,
                columns: ["startDate"],
            )
            try db.create(
                index: "idx_events_calendarId",
                on: Event.databaseTableName,
                columns: ["calendarId"],
            )

            // Recreate FTS content-sync table
            try db.create(virtualTable: "events_fts", using: FTS5()) { t in
                t.synchronize(withTable: Event.databaseTableName)
                t.column("title")
                t.column("organizer")
            }

            // -- EventOverrides: add calendarId and migrate to composite PK --
            try db.rename(table: EventOverride.databaseTableName, to: "event_overrides_old")

            try db.create(table: EventOverride.databaseTableName) { t in
                t.primaryKey {
                    t.column("eventId", .text)
                    t.column("calendarId", .text)
                }
                t.column("alertMinutes", .integer).notNull()
            }

            // Backfill calendarId from the events table so existing overrides
            // are correctly scoped. Orphan overrides (no matching event) are dropped.
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO \(EventOverride.databaseTableName) (eventId, calendarId, alertMinutes)
                SELECT eo.eventId, e.calendarId, eo.alertMinutes
                FROM event_overrides_old eo
                JOIN \(Event.databaseTableName) e ON e.id = eo.eventId
                """,
            )
            try db.drop(table: "event_overrides_old")
        }
    }
}
