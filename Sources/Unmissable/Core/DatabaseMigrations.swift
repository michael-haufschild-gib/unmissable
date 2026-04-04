import Foundation
import GRDB

// MARK: - Database Migrations

extension DatabaseManager {
    /// All database schema migrations, applied sequentially.
    static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()

        #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
        #endif

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

        migrator.registerMigration("v2-eventDetails") { db in
            let columns = try db.columns(in: Event.databaseTableName).map(\.name)
            if !columns.contains("description") {
                try db.alter(table: Event.databaseTableName) { t in
                    t.add(column: "description", .text)
                    t.add(column: "location", .text)
                    t.add(column: "attendees", .text).notNull().defaults(to: "[]")
                }
            }
        }

        migrator.registerMigration("v3-attachments") { db in
            let columns = try db.columns(in: Event.databaseTableName).map(\.name)
            if !columns.contains("attachments") {
                try db.alter(table: Event.databaseTableName) { t in
                    t.add(column: "attachments", .text).notNull().defaults(to: "[]")
                }
            }
        }

        migrator.registerMigration("v4-sourceProvider") { db in
            let columns = try db.columns(in: CalendarInfo.databaseTableName).map(\.name)
            if !columns.contains("sourceProvider") {
                try db.alter(table: CalendarInfo.databaseTableName) { t in
                    t.add(column: "sourceProvider", .text).notNull().defaults(to: "google")
                }
            }
        }

        migrator.registerMigration("v5-dropLegacySchemaVersion") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS schema_version")
        }

        migrator.registerMigration("v6-eventOverrides") { db in
            try db.create(table: EventOverride.databaseTableName, ifNotExists: true) { t in
                t.column("eventId", .text).primaryKey()
                t.column("alertMinutes", .integer).notNull()
            }
        }

        migrator.registerMigration("v7-calendarAlertMode") { db in
            let columns = try db.columns(in: CalendarInfo.databaseTableName).map(\.name)
            if !columns.contains("alertMode") {
                try db.alter(table: CalendarInfo.databaseTableName) { t in
                    t.add(column: "alertMode", .text).notNull().defaults(to: "overlay")
                }
            }
        }

        return migrator
    }()
}
