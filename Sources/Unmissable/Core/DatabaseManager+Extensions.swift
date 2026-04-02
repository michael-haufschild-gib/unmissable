import Foundation
import GRDB
import OSLog

private let extensionLogger = Logger(category: "DatabaseManager")

// MARK: - Search & Maintenance

extension DatabaseManager {
    /// Sanitizes user input for FTS5 MATCH by quoting each token.
    /// Prevents FTS syntax injection (e.g., `OR`, `AND`, `*`, `"`, parentheses).
    private func sanitizeFTSQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Split into whitespace-delimited tokens, wrap each in double quotes
        // (escaping any embedded double quotes), and join with spaces for AND semantics.
        return trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " ")
    }

    func searchEvents(query: String) async throws -> [Event] {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        let sanitized = sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else { return [] }

        return try await withTimeout(defaultTimeout) {
            try await dbQueue.read { db in
                try Event.fetchAll(
                    db,
                    sql: """
                    SELECT events.* FROM events
                    JOIN events_fts ON events.rowid = events_fts.rowid
                    WHERE events_fts MATCH ?
                    ORDER BY events_fts.rank
                    """, arguments: [sanitized]
                )
            }
        }
    }

    func performMaintenance() async throws {
        extensionLogger.info("Starting database maintenance")

        // Delete events older than 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        try await deleteOldEvents(before: thirtyDaysAgo)

        // Vacuum database outside a transaction (VACUUM cannot run inside a transaction).
        // Use longer timeout as VACUUM can take time on large DBs.
        guard let dbQueue else { return }

        try await withTimeout(60.0) {
            try await dbQueue.barrierWriteWithoutTransaction { db in
                try db.execute(sql: "VACUUM")
            }
        }

        extensionLogger.info("Database maintenance completed")
    }

    func resetDatabase() throws {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }

        try dbQueue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS events_fts")
            try db.execute(sql: "DROP TABLE IF EXISTS events")
            try db.execute(sql: "DROP TABLE IF EXISTS calendars")
            try db.execute(sql: "DROP TABLE IF EXISTS schema_version")
            try db.execute(sql: "DROP TABLE IF EXISTS grdb_migrations")
        }

        try Self.migrator.migrate(dbQueue)

        extensionLogger.info("Database reset completed")
    }
}

// MARK: - Test Helpers (DEBUG only)

#if DEBUG
    extension DatabaseManager {
        /// Escapes SQL LIKE wildcards and wraps in `%…%` for substring matching.
        private func likePattern(for raw: String) -> String {
            let escaped = raw
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            return "%\(escaped)%"
        }

        /// Delete events matching a specific ID pattern (for testing only)
        func deleteTestEvents(withIdPattern pattern: String) async throws {
            guard let dbQueue else { throw DatabaseError.notInitialized }

            let like = likePattern(for: pattern)
            let deletedCount = try await dbQueue.write { db in
                try Event
                    .filter(Event.Columns.id.like(like, escape: "\\"))
                    .deleteAll(db)
            }
            extensionLogger.info("Deleted \(deletedCount) test events with pattern: \(pattern)")
        }

        /// Delete test calendars matching a name pattern (for testing only)
        func deleteTestCalendars(withNamePattern pattern: String) async throws {
            guard let dbQueue else { throw DatabaseError.notInitialized }

            let like = likePattern(for: pattern)
            let deletedCount = try await dbQueue.write { db in
                try CalendarInfo
                    .filter(CalendarInfo.Columns.name.like(like, escape: "\\"))
                    .deleteAll(db)
            }
            extensionLogger.info("Deleted \(deletedCount) test calendars with pattern: \(pattern)")
        }

        /// Delete events matching a specific title pattern (for testing only)
        func deleteTestEventsByTitle(withPattern pattern: String) async throws {
            guard let dbQueue else { throw DatabaseError.notInitialized }

            let like = likePattern(for: pattern)
            let deletedCount = try await dbQueue.write { db in
                try Event
                    .filter(Event.Columns.title.like(like, escape: "\\"))
                    .deleteAll(db)
            }
            extensionLogger.info("Deleted \(deletedCount) test events with title pattern: \(pattern)")
        }
    }
#endif

// MARK: - Error Types

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
