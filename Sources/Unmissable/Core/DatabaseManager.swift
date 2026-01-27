import Foundation
import GRDB
import OSLog

@MainActor
final class DatabaseManager: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "DatabaseManager")
    private let debugLogger = DebugLogger(
        subsystem: "com.unmissable.app", category: "DatabaseManager"
    )
    private var dbQueue: DatabaseQueue?
    private let currentSchemaVersion = 3

    /// Indicates whether the database was successfully initialized
    @Published private(set) var isInitialized: Bool = false
    /// Contains error message if database initialization failed
    @Published private(set) var initializationError: String?

    static let shared = DatabaseManager()

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let unmissableURL = appSupportURL.appendingPathComponent("Unmissable")
            try fileManager.createDirectory(at: unmissableURL, withIntermediateDirectories: true)

            let dbURL = unmissableURL.appendingPathComponent("unmissable.db")

            dbQueue = try DatabaseQueue(path: dbURL.path)

            try dbQueue?.write { db in
                try setupSchema(db)
            }

            isInitialized = true
            initializationError = nil
            logger.info("Database initialized at: \(dbURL.path)")
        } catch {
            logger.error("Failed to setup database: \(error.localizedDescription)")
            isInitialized = false
            initializationError = "Database setup failed: \(error.localizedDescription)"
            // Graceful degradation instead of crash - app can still run with limited functionality
        }
    }

    private func setupSchema(_ db: Database) throws {
        // Enable foreign keys
        try db.execute(sql: "PRAGMA foreign_keys = ON")

        // Get current schema version
        let currentVersion = try getCurrentSchemaVersion(db)

        if currentVersion == 0 {
            // Fresh install
            try createInitialSchema(db)
            try setSchemaVersion(db, version: currentSchemaVersion)
        } else if currentVersion < currentSchemaVersion {
            // Migration needed
            try migrateSchema(db, from: currentVersion, to: currentSchemaVersion)
        }
    }

    private func getCurrentSchemaVersion(_ db: Database) throws -> Int {
        // Check if schema_version table exists
        let tableExists =
            try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name='schema_version'"
            ) ?? false

        if !tableExists {
            return 0
        }

        return try Int.fetchOne(db, sql: "SELECT version FROM schema_version LIMIT 1") ?? 0
    }

    private func setSchemaVersion(_ db: Database, version: Int) throws {
        try db.create(table: "schema_version", ifNotExists: true) { t in
            t.column("version", .integer).notNull()
        }

        try db.execute(sql: "DELETE FROM schema_version")
        try db.execute(sql: "INSERT INTO schema_version (version) VALUES (?)", arguments: [version])
    }

    private func createInitialSchema(_ db: Database) throws {
        try createTables(db)
    }

    private func migrateSchema(_ db: Database, from oldVersion: Int, to newVersion: Int) throws {
        logger.info("Migrating database from version \(oldVersion) to \(newVersion)")

        for version in (oldVersion + 1) ... newVersion {
            try performMigration(db, to: version)
        }

        try setSchemaVersion(db, version: newVersion)
        logger.info("Database migration completed")
    }

    private func performMigration(_ db: Database, to version: Int) throws {
        switch version {
        case 1:
            // Initial version, no migration needed
            break
        case 2:
            // Add description, location, and attendees columns to events table
            try db.alter(table: Event.databaseTableName) { t in
                t.add(column: "description", .text)
                t.add(column: "location", .text)
                t.add(column: "attendees", .text).notNull().defaults(to: "[]")
            }
            logger.info("Migrated to version 2: Added description, location, and attendees columns")
        case 3:
            // Add attachments column to events table for Google Drive file attachments
            try db.alter(table: Event.databaseTableName) { t in
                t.add(column: "attachments", .text).notNull().defaults(to: "[]")
            }
            logger.info("Migrated to version 3: Added attachments column")
        default:
            throw DatabaseError.migrationFailed("Unknown migration version: \(version)")
        }
    }

    private func createTables(_ db: Database) throws {
        // Create events table
        try db.create(table: Event.databaseTableName, ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("startDate", .datetime).notNull()
            t.column("endDate", .datetime).notNull()
            t.column("organizer", .text)
            t.column("description", .text)
            t.column("location", .text)
            t.column("attendees", .text).notNull().defaults(to: "[]")
            t.column("attachments", .text).notNull().defaults(to: "[]")
            t.column("isAllDay", .boolean).notNull().defaults(to: false)
            t.column("calendarId", .text).notNull()
            t.column("timezone", .text).notNull()
            t.column("links", .text).notNull().defaults(to: "[]")
            t.column("meetingLinks", .text).notNull().defaults(to: "[]")
            t.column("provider", .text)
            t.column("snoozeUntil", .datetime)
            t.column("autoJoinEnabled", .boolean).notNull().defaults(to: false)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        // Create indexes
        try db.create(
            index: "idx_events_startDate", on: Event.databaseTableName, columns: ["startDate"],
            ifNotExists: true
        )
        try db.create(
            index: "idx_events_calendarId", on: Event.databaseTableName, columns: ["calendarId"],
            ifNotExists: true
        )

        // Create calendars table
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

        // Create full-text search for events - with safe creation
        try createFTSTableSafely(db)
    }

    private func createFTSTableSafely(_ db: Database) throws {
        // Check if FTS table already exists
        let ftsExists =
            try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name='events_fts'"
            ) ?? false

        if !ftsExists {
            try db.create(virtualTable: "events_fts", using: FTS5()) { t in
                t.synchronize(withTable: Event.databaseTableName)
                t.column("title")
                t.column("organizer")
            }
            logger.info("Created FTS table for events")
        } else {
            logger.info("FTS table already exists, skipping creation")
        }
    }

    // MARK: - Event Operations

    func saveEvents(_ events: [Event]) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        // Log first event being saved to verify data
        if let firstEvent = events.first {
            debugLogger.info("💾 SAVING EVENT TO DATABASE:")
            debugLogger.info("   - Title: \(firstEvent.title)")
            debugLogger.info(
                "   - Description being saved: \(firstEvent.description != nil ? "YES (\(firstEvent.description!.count) chars)" : "NO")"
            )
            debugLogger.info("   - Location being saved: \(firstEvent.location != nil ? "YES" : "NO")")
            debugLogger.info("   - Attendees being saved: \(firstEvent.attendees.count) attendees")
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
        let events = try await withTimeout(defaultTimeout) {
            try await dbQueue.read { db in
                try Event
                    .filter(Event.Columns.startDate > now)
                    .order(Event.Columns.startDate)
                    .limit(limit)
                    .fetchAll(db)
            }
        }

        // Log first fetched event to verify data retrieval
        if let firstEvent = events.first {
            debugLogger.info("📤 FETCHED EVENT FROM DATABASE:")
            debugLogger.info("   - Title: \(firstEvent.title)")
            debugLogger.info(
                "   - Description fetched: \(firstEvent.description != nil ? "YES (\(firstEvent.description!.count) chars)" : "NO")"
            )
            debugLogger.info("   - Location fetched: \(firstEvent.location != nil ? "YES" : "NO")")
            debugLogger.info("   - Attendees fetched: \(firstEvent.attendees.count) attendees")
        }

        return events
    }

    func fetchStartedMeetings(limit: Int = 10) async throws -> [Event] {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        let now = Date()
        let events = try await withTimeout(defaultTimeout) {
            try await dbQueue.read { db in
                try Event
                    .filter(Event.Columns.startDate <= now && Event.Columns.endDate > now)
                    .order(Event.Columns.startDate.desc) // Most recently started first
                    .limit(limit)
                    .fetchAll(db)
            }
        }

        debugLogger.info("📤 FETCHED \(events.count) STARTED MEETINGS FROM DATABASE")
        if let firstEvent = events.first {
            debugLogger.info("   - First started meeting: \(firstEvent.title)")
            debugLogger.info(
                "   - Started at: \(firstEvent.startDate), ends at: \(firstEvent.endDate)"
            )
        }

        return events
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

    #if DEBUG
        /// Delete events matching a specific ID pattern (for testing only)
        /// Pattern is safely escaped to prevent SQL injection
        func deleteTestEvents(withIdPattern pattern: String) async throws {
            guard let dbQueue else {
                throw DatabaseError.notInitialized
            }

            // Escape special LIKE characters and use parameterized query
            let escapedPattern = pattern
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let likePattern = "%\(escapedPattern)%"

            let deletedCount = try await dbQueue.write { db in
                try Event
                    .filter(Event.Columns.id.like(likePattern, escape: "\\"))
                    .deleteAll(db)
            }

            logger.info("Deleted \(deletedCount) test events with pattern: \(pattern)")
        }

        /// Delete test calendars matching a name pattern (for testing only)
        /// Pattern is safely escaped to prevent SQL injection
        func deleteTestCalendars(withNamePattern pattern: String) async throws {
            guard let dbQueue else {
                throw DatabaseError.notInitialized
            }

            // Escape special LIKE characters and use parameterized query
            let escapedPattern = pattern
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let likePattern = "%\(escapedPattern)%"

            let deletedCount = try await dbQueue.write { db in
                try CalendarInfo
                    .filter(CalendarInfo.Columns.name.like(likePattern, escape: "\\"))
                    .deleteAll(db)
            }

            logger.info("Deleted \(deletedCount) test calendars with pattern: \(pattern)")
        }

        /// Delete events matching a specific title pattern (for testing only)
        /// Pattern is safely escaped to prevent SQL injection
        func deleteTestEventsByTitle(withPattern pattern: String) async throws {
            guard let dbQueue else {
                throw DatabaseError.notInitialized
            }

            // Escape special LIKE characters and use parameterized query
            let escapedPattern = pattern
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let likePattern = "%\(escapedPattern)%"

            let deletedCount = try await dbQueue.write { db in
                try Event
                    .filter(Event.Columns.title.like(likePattern, escape: "\\"))
                    .deleteAll(db)
            }

            logger.info("Deleted \(deletedCount) test events with title pattern: \(pattern)")
        }
    #endif

    func searchEvents(query: String) async throws -> [Event] {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await withTimeout(defaultTimeout) {
            try await dbQueue.read { db in
                let eventIds =
                    try String
                        .fetchAll(
                            db,
                            sql: """
                            SELECT id FROM events_fts
                            WHERE events_fts MATCH ?
                            ORDER BY rank
                            """, arguments: [query]
                        )

                return
                    try Event
                        .filter(eventIds.contains(Event.Columns.id))
                        .fetchAll(db)
            }
        }
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

    // MARK: - Timeout Wrapper

    /// Default timeout for database operations (30 seconds)
    private let defaultTimeout: TimeInterval = 30.0

    /// Executes an async operation with a timeout to prevent indefinite hangs
    private func withTimeout<T: Sendable>(
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

    // MARK: - Database Maintenance

    func performMaintenance() async throws {
        logger.info("Starting database maintenance")

        // Delete events older than 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        try await deleteOldEvents(before: thirtyDaysAgo)

        // Vacuum database (use longer timeout as VACUUM can take time on large DBs)
        guard let dbQueue else { return }

        try await withTimeout(60.0) {
            try await dbQueue.write { db in
                try db.execute(sql: "VACUUM")
            }
        }

        logger.info("Database maintenance completed")
    }

    func resetDatabase() throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        try dbQueue.write { db in
            // Drop existing tables
            try db.execute(sql: "DROP TABLE IF EXISTS events_fts")
            try db.execute(sql: "DROP TABLE IF EXISTS events")
            try db.execute(sql: "DROP TABLE IF EXISTS calendars")
            try db.execute(sql: "DROP TABLE IF EXISTS schema_version")

            // Recreate schema
            try setupSchema(db)
        }

        logger.info("Database reset completed")
    }
}

enum DatabaseError: LocalizedError {
    case notInitialized
    case migrationFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            "Database not initialized"
        case let .migrationFailed(message):
            "Database migration failed: \(message)"
        case .timeout:
            "Database operation timed out"
        }
    }
}
