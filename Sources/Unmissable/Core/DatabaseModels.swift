import Foundation
import GRDB
import OSLog

private nonisolated let logger = Logger(category: "DatabaseModels")

// MARK: - Cached JSON Coders

/// Shared coders for all row encode/decode operations. JSONEncoder and JSONDecoder
/// are thread-safe when their configuration is not mutated between calls — no custom
/// strategies are set here, so sharing a single instance avoids hundreds of allocations
/// per sync cycle.
private nonisolated(unsafe) let cachedDecoder = JSONDecoder()
private nonisolated(unsafe) let cachedEncoder = JSONEncoder()

// MARK: - JSON Column Helpers

/// Decodes a JSON-encoded string column into a Decodable value, returning `defaultValue` on failure.
private nonisolated func decodeJSONColumn<T: Decodable>(
    _ row: Row, _ column: Column, default defaultValue: T,
) -> T {
    let raw = row[column] as? String ?? "[]"
    guard let data = raw.data(using: .utf8) else { return defaultValue }
    do {
        return try cachedDecoder.decode(T.self, from: data)
    } catch {
        logger.error("Failed to decode \(column.name): \(error.localizedDescription)")
        return defaultValue
    }
}

/// Decodes a JSON-encoded `[String]` column into `[URL]`, dropping unparseable entries.
private nonisolated func decodeJSONURLColumn(_ row: Row, _ column: Column) -> [URL] {
    let strings: [String] = decodeJSONColumn(row, column, default: [])
    return strings.compactMap { URL(string: $0) }
}

/// Encodes an Encodable value as a JSON string into a persistence container column.
private nonisolated func encodeJSONColumn(
    _ value: some Encodable, into container: inout PersistenceContainer, _ column: Column,
) {
    do {
        let data = try cachedEncoder.encode(value)
        container[column] = String(data: data, encoding: .utf8) ?? "[]"
    } catch {
        logger.error("Failed to encode \(column.name): \(error.localizedDescription)")
        container[column] = "[]"
    }
}

/// Encodes `[URL]` as a JSON `[String]` into a persistence container column.
private nonisolated func encodeJSONURLColumn(
    _ value: [URL], into container: inout PersistenceContainer, _ column: Column,
) {
    encodeJSONColumn(value.map(\.absoluteString), into: &container, column)
}

nonisolated extension Event {
    static let databaseTableName = "events"

    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let startDate = Column("startDate")
        static let endDate = Column("endDate")
        static let organizer = Column("organizer")
        static let description = Column("description")
        static let location = Column("location")
        static let attendees = Column("attendees")
        static let attachments = Column("attachments")
        static let isAllDay = Column("isAllDay")
        static let calendarId = Column("calendarId")
        static let timezone = Column("timezone")
        static let links = Column("links")
        static let provider = Column("provider")
        static let snoozeUntil = Column("snoozeUntil")
        static let autoJoinEnabled = Column("autoJoinEnabled")
        static let createdAt = Column("createdAt")
        static let updatedAt = Column("updatedAt")
    }

    init(row: Row) {
        id = row[Columns.id]
        title = row[Columns.title]
        startDate = row[Columns.startDate]
        endDate = row[Columns.endDate]
        organizer = row[Columns.organizer]
        description = row[Columns.description]
        location = row[Columns.location]

        attendees = decodeJSONColumn(row, Columns.attendees, default: [Attendee]())
        attachments = decodeJSONColumn(row, Columns.attachments, default: [EventAttachment]())

        isAllDay = row[Columns.isAllDay]
        calendarId = row[Columns.calendarId]
        timezone = row[Columns.timezone]

        links = decodeJSONURLColumn(row, Columns.links)

        // Decode provider
        if let providerRawValue = row[Columns.provider] as? String {
            provider = Provider(rawValue: providerRawValue)
        } else {
            provider = nil
        }

        snoozeUntil = row[Columns.snoozeUntil]
        autoJoinEnabled = row[Columns.autoJoinEnabled]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.title] = title
        container[Columns.startDate] = startDate
        container[Columns.endDate] = endDate
        container[Columns.organizer] = organizer
        container[Columns.description] = description
        container[Columns.location] = location

        encodeJSONColumn(attendees, into: &container, Columns.attendees)
        encodeJSONColumn(attachments, into: &container, Columns.attachments)

        container[Columns.isAllDay] = isAllDay
        container[Columns.calendarId] = calendarId
        container[Columns.timezone] = timezone

        encodeJSONURLColumn(links, into: &container, Columns.links)

        container[Columns.provider] = provider?.rawValue
        container[Columns.snoozeUntil] = snoozeUntil
        container[Columns.autoJoinEnabled] = autoJoinEnabled
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

nonisolated extension Event: FetchableRecord, PersistableRecord {}

nonisolated extension CalendarInfo {
    static let databaseTableName = "calendars"

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let description = Column("description")
        static let isSelected = Column("isSelected")
        static let isPrimary = Column("isPrimary")
        static let colorHex = Column("colorHex")
        static let sourceProvider = Column("sourceProvider")
        static let alertMode = Column("alertMode")
        static let lastSyncAt = Column("lastSyncAt")
        static let createdAt = Column("createdAt")
        static let updatedAt = Column("updatedAt")
    }

    init(row: Row) {
        id = row[Columns.id]
        name = row[Columns.name]
        description = row[Columns.description]
        isSelected = row[Columns.isSelected]
        isPrimary = row[Columns.isPrimary]
        colorHex = row[Columns.colorHex]
        if let providerRaw = row[Columns.sourceProvider] as? String,
           let provider = CalendarProviderType(rawValue: providerRaw)
        {
            sourceProvider = provider
        } else {
            // Legacy rows from before multi-provider support lack a provider column.
            // Default to .google since that was the only provider at the time.
            if let rawValue = row[Columns.sourceProvider] as? String {
                logger.warning("Unknown calendar provider '\(rawValue)' — defaulting to .google")
            }
            sourceProvider = .google
        }
        if let modeRaw = row[Columns.alertMode] as? String,
           let mode = AlertMode(rawValue: modeRaw)
        {
            alertMode = mode
        } else {
            alertMode = .overlay
        }
        lastSyncAt = row[Columns.lastSyncAt]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.description] = description
        container[Columns.isSelected] = isSelected
        container[Columns.isPrimary] = isPrimary
        container[Columns.colorHex] = colorHex
        container[Columns.sourceProvider] = sourceProvider.rawValue
        container[Columns.alertMode] = alertMode.rawValue
        container[Columns.lastSyncAt] = lastSyncAt
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

nonisolated extension CalendarInfo: FetchableRecord, PersistableRecord {}

// MARK: - EventOverride

nonisolated extension EventOverride {
    static let databaseTableName = "event_overrides"

    enum Columns {
        static let eventId = Column("eventId")
        static let alertMinutes = Column("alertMinutes")
    }

    init(row: Row) {
        eventId = row[Columns.eventId]
        alertMinutes = row[Columns.alertMinutes]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.eventId] = eventId
        container[Columns.alertMinutes] = alertMinutes
    }
}

nonisolated extension EventOverride: FetchableRecord, PersistableRecord {}
