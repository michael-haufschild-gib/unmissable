import Foundation
import GRDB
import OSLog

/// Protocol enabling dependency injection for database operations.
/// Covers all methods consumed by CalendarService, SyncManager, and ServiceContainer.
nonisolated protocol DatabaseManaging: Sendable {
    // MARK: - Event Operations

    func saveEvents(_ events: [Event]) async throws
    func replaceEvents(for calendarId: String, with events: [Event]) async throws
    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [Event]
    func fetchUpcomingEvents(limit: Int) async throws -> [Event]
    func fetchStartedMeetings(limit: Int) async throws -> [Event]
    func deleteEventsForCalendar(_ calendarId: String) async throws
    func deleteOldEvents(before date: Date) async throws

    // MARK: - Calendar Operations

    func saveCalendars(_ calendars: [CalendarInfo]) async throws
    func fetchCalendars() async throws -> [CalendarInfo]
    func updateCalendarSyncTime(_ calendarId: String) async throws

    // MARK: - Provider-Scoped Operations

    func fetchCalendars(for provider: CalendarProviderType) async throws -> [CalendarInfo]
    func deleteCalendarsForProvider(_ provider: CalendarProviderType) async throws
    func deleteEventsForProvider(_ provider: CalendarProviderType) async throws
    func deleteAllDataForProvider(_ provider: CalendarProviderType) async throws

    /// Merges upstream calendars for a provider, preserving user-controlled fields
    /// (isSelected, alertMode) for existing calendars, inserting new ones with defaults,
    /// and deleting local calendars that disappeared upstream.
    func mergeCalendars(provider: CalendarProviderType, upstream: [CalendarInfo]) async throws

    // MARK: - Alert Overrides

    func fetchAlertOverride(for eventId: String, calendarId: String) async throws -> Int?
    /// Returns all alert overrides keyed by compound key (eventId_calendarId).
    func fetchAllAlertOverrides() async throws -> [String: Int]
    func saveAlertOverride(eventId: String, calendarId: String, minutes: Int?) async throws

    // MARK: - Search & Maintenance

    func searchEvents(query: String) async throws -> [Event]
    func performMaintenance() async throws

    // MARK: - Initialization Status

    var initializationError: String? { get async }

    /// Re-run database initialization. Returns `nil` on success or the error description on failure.
    @discardableResult
    func reinitialize() async -> String?
}

extension DatabaseManaging {
    var initializationError: String? {
        nil
    }

    // Protocol default provides no-op for optional capability
    // swiftlint:disable:next async_without_await
    func reinitialize() async -> String? {
        nil
    }
}

actor DatabaseManager: DatabaseManaging {
    private let logger = Logger(category: "DatabaseManager")

    private(set) var dbQueue: DatabaseQueue?
    private(set) var isInitialized: Bool = false
    private(set) var initializationError: String?

    /// Production convenience initializer using Application Support directory.
    init() {
        let fileManager = FileManager.default
        let dbURL: URL
        do {
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true,
            )
            let unmissableURL = appSupportURL.appendingPathComponent("Unmissable")
            try fileManager.createDirectory(at: unmissableURL, withIntermediateDirectories: true)
            dbURL = unmissableURL.appendingPathComponent("unmissable.db")
        } catch {
            logger.error("Failed to resolve database path: \(PrivacyUtils.redactedError(error))")
            isInitialized = false
            initializationError = "Database path resolution failed: \(error.localizedDescription)"
            return
        }
        do {
            let queue = try DatabaseQueue(path: dbURL.path)
            dbQueue = queue
            try Self.migrator.migrate(queue)
            isInitialized = true
            initializationError = nil
            logger.info("Database initialized at: \(PrivacyUtils.redactedPath(dbURL.path))")
        } catch {
            logger.error("Failed to setup database: \(PrivacyUtils.redactedError(error))")
            isInitialized = false
            initializationError = "Database setup failed: \(error.localizedDescription)"
        }
    }

    /// Testable initializer with explicit database path.
    init(databaseURL: URL) {
        do {
            let queue = try DatabaseQueue(path: databaseURL.path)
            dbQueue = queue
            try Self.migrator.migrate(queue)
            isInitialized = true
            initializationError = nil
            logger.info("Database initialized at: \(PrivacyUtils.redactedPath(databaseURL.path))")
        } catch {
            logger.error("Failed to setup database: \(PrivacyUtils.redactedError(error))")
            isInitialized = false
            initializationError = "Database setup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Reinitialization

    /// Re-runs the production initialization logic (path resolution, queue creation, migrations).
    /// Returns `nil` on success or the error description on failure.
    @discardableResult
    func reinitialize() -> String? {
        let fileManager = FileManager.default
        let dbURL: URL
        do {
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true,
            )
            let unmissableURL = appSupportURL.appendingPathComponent("Unmissable")
            try fileManager.createDirectory(at: unmissableURL, withIntermediateDirectories: true)
            dbURL = unmissableURL.appendingPathComponent("unmissable.db")
        } catch {
            let message = "Database path resolution failed: \(error.localizedDescription)"
            logger.error("\(message)")
            isInitialized = false
            initializationError = message
            return message
        }
        do {
            let queue = try DatabaseQueue(path: dbURL.path)
            dbQueue = queue
            try Self.migrator.migrate(queue)
            isInitialized = true
            initializationError = nil
            logger.info("Database reinitialized at: \(dbURL.path)")
            return nil
        } catch {
            let message = "Database setup failed: \(error.localizedDescription)"
            logger.error("\(message)")
            isInitialized = false
            initializationError = message
            return message
        }
    }

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

        logger
            .info(
                "Atomically replaced events for calendar \(PrivacyUtils.redactedCalendarId(calendarId)): \(events.count) events saved",
            )
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

        logger.info("Deleted events for calendar: \(PrivacyUtils.redactedCalendarId(calendarId))")
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
                    """, arguments: [Date(), Date(), calendarId],
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

        // Single atomic query using a subquery instead of two-step read+delete.
        // Prevents a reentrancy window where a calendar could be added between
        // fetching IDs and deleting events.
        let providerRaw = provider.rawValue
        let deletedCount = try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                try db.execute(
                    sql: """
                    DELETE FROM events
                    WHERE calendarId IN (
                        SELECT id FROM calendars WHERE sourceProvider = ?
                    )
                    """,
                    arguments: [providerRaw],
                )
                return db.changesCount
            }
        }

        logger.info(
            "Deleted \(deletedCount) events for provider \(provider.rawValue)",
        )
    }

    func deleteAllDataForProvider(_ provider: CalendarProviderType) async throws {
        try await deleteEventsForProvider(provider)
        try await deleteCalendarsForProvider(provider)
    }

    func mergeCalendars(provider: CalendarProviderType, upstream: [CalendarInfo]) async throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        try await withTimeout(defaultTimeout) {
            try await dbQueue.write { db in
                // Fetch existing calendars for this provider
                let existing = try CalendarInfo
                    .filter(CalendarInfo.Columns.sourceProvider == provider.rawValue)
                    .fetchAll(db)
                let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
                let upstreamIds = Set(upstream.map(\.id))

                // Upsert upstream calendars, preserving user-controlled fields
                for cal in upstream {
                    if let local = existingById[cal.id] {
                        // Update API-controlled fields, preserve user choices
                        let merged = CalendarInfo(
                            id: cal.id,
                            name: cal.name,
                            description: cal.description,
                            isSelected: local.isSelected,
                            isPrimary: cal.isPrimary,
                            colorHex: cal.colorHex,
                            sourceProvider: cal.sourceProvider,
                            alertMode: local.alertMode,
                            lastSyncAt: local.lastSyncAt,
                            createdAt: local.createdAt,
                            updatedAt: Date(),
                        )
                        try merged.save(db)
                    } else {
                        // New calendar — insert with defaults from upstream
                        try cal.save(db)
                    }
                }

                // Delete calendars that disappeared upstream
                let staleIds = Set(existingById.keys).subtracting(upstreamIds)
                if !staleIds.isEmpty {
                    try CalendarInfo
                        .filter(staleIds.contains(CalendarInfo.Columns.id))
                        .deleteAll(db)
                }
            }
        }

        logger.info(
            "Merged \(upstream.count) calendars for provider \(provider.rawValue)",
        )
    }

    // MARK: - Timeout Wrapper

    /// Default timeout for database operations (30 seconds)
    let defaultTimeout: TimeInterval = 30.0

    /// Executes an async operation with a timeout to prevent indefinite hangs
    func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T,
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
