import Foundation
import GRDB
import OSLog

final class DatabaseManager: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "DatabaseManager")
    private(set) var dbQueue: DatabaseQueue?

    /// Indicates whether the database was successfully initialized
    private(set) var isInitialized: Bool = false
    /// Contains error message if database initialization failed
    private(set) var initializationError: String?

    static let shared = DatabaseManager()

    /// Production convenience initializer using Application Support directory.
    init() {
        let fileManager = FileManager.default
        let dbURL: URL
        do {
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let unmissableURL = appSupportURL.appendingPathComponent("Unmissable")
            try fileManager.createDirectory(at: unmissableURL, withIntermediateDirectories: true)
            dbURL = unmissableURL.appendingPathComponent("unmissable.db")
        } catch {
            logger.error("Failed to resolve database path: \(error.localizedDescription)")
            isInitialized = false
            initializationError = "Database path resolution failed: \(error.localizedDescription)"
            return
        }
        setupDatabase(at: dbURL)
    }

    /// Testable initializer with explicit database path.
    init(databaseURL: URL) {
        setupDatabase(at: databaseURL)
    }

    private func setupDatabase(at dbURL: URL) {
        do {
            let queue = try DatabaseQueue(path: dbURL.path)
            dbQueue = queue

            try Self.migrator.migrate(queue)

            // Drop legacy schema_version table left by the old hand-rolled migration system
            try queue.write { db in
                try db.execute(sql: "DROP TABLE IF EXISTS schema_version")
            }

            isInitialized = true
            initializationError = nil
            logger.info("Database initialized at: \(dbURL.path)")
        } catch {
            logger.error("Failed to setup database: \(error.localizedDescription)")
            isInitialized = false
            initializationError = "Database setup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Migrations (GRDB DatabaseMigrator)

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
                index: "idx_events_startDate", on: Event.databaseTableName,
                columns: ["startDate"], ifNotExists: true
            )
            try db.create(
                index: "idx_events_calendarId", on: Event.databaseTableName,
                columns: ["calendarId"], ifNotExists: true
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
                sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name='events_fts'"
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

        return migrator
    }()

    // MARK: - Event Operations

    func saveEvents(_ events: [Event]) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                for event in events {
                    try event.save(db)
                }
            }
        }

        logger.info("Saved \(events.count) events to database")
    }

    func replaceEvents(for calendarId: String, with events: [Event]) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                // Delete existing events for this calendar
                try Event
                    .filter(Event.Columns.calendarId == calendarId)
                    .deleteAll(db)

                // Insert new events
                for event in events {
                    try event.save(db)
                }
            }
        }

        logger.info("Atomically replaced events for calendar \(calendarId): \(events.count) events saved")
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [Event] {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await withTimeout(defaultTimeout) {
            try await dbQueue.read { db in
                try Event
                    .filter(Event.Columns.startDate >= startDate)
                    .filter(Event.Columns.startDate <= endDate)
                    .order(Event.Columns.startDate)
                    .fetchAll(db)
            }
        }
    }

    func fetchUpcomingEvents(limit: Int = 10) async throws -> [Event] {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        let now = Date()
        return try await withTimeout(defaultTimeout) {
            try await dbQueue.read { db in
                try Event
                    .filter(Event.Columns.startDate > now)
                    .order(Event.Columns.startDate)
                    .limit(limit)
                    .fetchAll(db)
            }
        }
    }

    func fetchStartedMeetings(limit: Int = 10) async throws -> [Event] {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        let now = Date()
        return try await withTimeout(defaultTimeout) {
            try await dbQueue.read { db in
                try Event
                    .filter(Event.Columns.startDate <= now && Event.Columns.endDate > now)
                    .order(Event.Columns.startDate.desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        }
    }

    func deleteEventsForCalendar(_ calendarId: String) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        _ = try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                try Event
                    .filter(Event.Columns.calendarId == calendarId)
                    .deleteAll(db)
            }
        }

        logger.info("Deleted events for calendar: \(calendarId)")
    }

    func deleteOldEvents(before date: Date) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        let deletedCount = try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                try Event
                    .filter(Event.Columns.endDate < date)
                    .deleteAll(db)
            }
        }

        logger.info("Deleted \(deletedCount) old events")
    }

    // MARK: - Calendar Operations

    func saveCalendars(_ calendars: [CalendarInfo]) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                for calendar in calendars {
                    try calendar.save(db)
                }
            }
        }

        logger.info("Saved \(calendars.count) calendars to database")
    }

    func fetchCalendars() async throws -> [CalendarInfo] {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await withTimeout(defaultTimeout) {
            try await dbQueue.read { db in
                try CalendarInfo
                    .order(CalendarInfo.Columns.isPrimary.desc, CalendarInfo.Columns.name)
                    .fetchAll(db)
            }
        }
    }

    func updateCalendarSyncTime(_ calendarId: String) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                try db.execute(
                    sql: """
                    UPDATE calendars
                    SET lastSyncAt = ?, updatedAt = ?
                    WHERE id = ?
                    """, arguments: [Date(), Date(), calendarId]
                )
            }
        }
    }

    // MARK: - Provider-Scoped Operations

    func fetchCalendars(for provider: CalendarProviderType) async throws -> [CalendarInfo] {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await withTimeout(defaultTimeout) {
            try await dbQueue.read { db in
                try CalendarInfo
                    .filter(CalendarInfo.Columns.sourceProvider == provider.rawValue)
                    .order(CalendarInfo.Columns.isPrimary.desc, CalendarInfo.Columns.name)
                    .fetchAll(db)
            }
        }
    }

    func deleteCalendarsForProvider(_ provider: CalendarProviderType) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        let deletedCount = try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                try CalendarInfo
                    .filter(CalendarInfo.Columns.sourceProvider == provider.rawValue)
                    .deleteAll(db)
            }
        }

        logger.info("Deleted \(deletedCount) calendars for provider \(provider.rawValue)")
    }

    func deleteEventsForProvider(_ provider: CalendarProviderType) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        let calendarIds = try await fetchCalendars(for: provider).map(\.id)
        guard !calendarIds.isEmpty else { return }

        let deletedCount = try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                try Event
                    .filter(calendarIds.contains(Event.Columns.calendarId))
                    .deleteAll(db)
            }
        }

        logger.info(
            "Deleted \(deletedCount) events for provider \(provider.rawValue) across \(calendarIds.count) calendars"
        )
    }

    func deleteAllDataForProvider(_ provider: CalendarProviderType) async throws {
        try await deleteEventsForProvider(provider)
        try await deleteCalendarsForProvider(provider)
    }

    // MARK: - Timeout Wrapper

    /// Default timeout for database operations (30 seconds)
    let defaultTimeout: TimeInterval = 30.0

    /// Executes an async operation with a timeout to prevent indefinite hangs
    func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw DatabaseError.timeout
            }
            guard let result = try await group.next() else {
                throw DatabaseError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}
