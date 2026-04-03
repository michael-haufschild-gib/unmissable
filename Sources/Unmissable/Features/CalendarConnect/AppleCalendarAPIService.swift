import EventKit
import Foundation
import OSLog

/// Fetches calendars and events from macOS Calendar via EventKit.
/// Supports iCloud, Exchange, CalDAV, and any other source configured in System Settings.
@MainActor
final class AppleCalendarAPIService: ObservableObject, CalendarAPIProviding {
    private let logger = Logger(category: "AppleCalendarAPI")
    private let eventStore: EKEventStore
    private let linkParser: LinkParser

    // MARK: - Constants

    private static let maxTitleLength = 500
    private static let maxDescriptionLength = 10_000
    private static let maxLocationLength = 1000
    private static let maxOrganizerLength = 320
    private static let colorComponentScale: CGFloat = 255
    private static let minColorComponents = 3

    @Published
    var calendars: [CalendarInfo] = []
    @Published
    var events: [Event] = []
    @Published
    var lastError: String?

    init(eventStore: EKEventStore = EKEventStore(), linkParser: LinkParser) {
        self.eventStore = eventStore
        self.linkParser = linkParser
    }

    @discardableResult
    // Protocol conformance: CalendarAPIProviding requires async signature
    // swiftlint:disable:next async_without_await
    func fetchCalendars() async -> [CalendarInfo] {
        logger.debug("Fetching Apple Calendar list")
        lastError = nil

        let ekCalendars = eventStore.calendars(for: .event)
        calendars = ekCalendars.map { convertToCalendarInfo($0) }

        logger.debug("Fetched \(self.calendars.count) Apple calendars")
        return calendars
    }

    @discardableResult
    // Protocol conformance: CalendarAPIProviding requires async signature
    // swiftlint:disable:next async_without_await
    func fetchEvents(for calendarIds: [String], from startDate: Date, to endDate: Date) async
        -> CalendarFetchResults
    {
        logger.debug("Fetching Apple Calendar events for \(calendarIds.count) calendars")
        lastError = nil

        let ekCalendars = eventStore.calendars(for: .event).filter { calendarIds.contains($0.calendarIdentifier) }
        let matchedIds = Set(ekCalendars.map(\.calendarIdentifier))

        // Initialize results for all requested IDs. Calendars with no matching
        // EKCalendar (e.g., deleted from Apple Calendar) get .success([]) — the
        // events from a removed calendar are genuinely zero.
        var results: CalendarFetchResults = [:]
        for calendarId in calendarIds {
            results[calendarId] = .success([])
        }

        guard !ekCalendars.isEmpty else {
            logger.warning("No matching Apple calendars found for provided IDs")
            events = []
            return results
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: ekCalendars,
        )

        let ekEvents = eventStore.events(matching: predicate)

        let convertedEvents = ekEvents.compactMap { convertToEvent($0) }
            .sorted { $0.startDate < $1.startDate }
        events = convertedEvents

        // Group events by calendar ID and populate results
        let eventsByCalendar = Dictionary(grouping: convertedEvents) { $0.calendarId }
        for calendarId in matchedIds {
            results[calendarId] = .success(eventsByCalendar[calendarId] ?? [])
        }

        logger.debug("Fetched \(convertedEvents.count) Apple Calendar events")
        return results
    }

    // MARK: - Conversion

    private func convertToCalendarInfo(_ ekCalendar: EKCalendar) -> CalendarInfo {
        let isPrimary = ekCalendar.calendarIdentifier == eventStore.defaultCalendarForNewEvents?.calendarIdentifier
        return CalendarInfo(
            id: ekCalendar.calendarIdentifier,
            name: ekCalendar.title,
            description: sourceDescription(for: ekCalendar),
            isSelected: isPrimary,
            isPrimary: isPrimary,
            colorHex: ekCalendar.cgColor.flatMap { hexFromCGColor($0) },
            sourceProvider: .apple,
        )
    }

    /// Truncates a string to a maximum length. Defense-in-depth against oversized calendar data.
    private static func truncate(_ string: String?, maxLength: Int) -> String? {
        guard let string, string.count > maxLength else { return string }
        return String(string.prefix(maxLength))
    }

    private func convertToEvent(_ ekEvent: EKEvent) -> Event? {
        guard let startDate = ekEvent.startDate,
              let endDate = ekEvent.endDate
        else {
            return nil
        }

        // Skip cancelled events
        if ekEvent.status == .canceled {
            return nil
        }

        // Skip declined events
        if let selfAttendee = ekEvent.attendees?.first(where: \.isCurrentUser),
           selfAttendee.participantStatus == .declined
        {
            return nil
        }

        let attendees = (ekEvent.attendees ?? []).compactMap { convertAttendee($0) }
        let links = extractMeetingLinks(from: ekEvent)
        let provider = linkParser.detectPrimaryLink(from: links).map { Provider.detect(from: $0) }

        // Truncate fields to defend against oversized calendar data
        let truncatedTitle = Self.truncate(ekEvent.title, maxLength: Self.maxTitleLength) ?? "Untitled Event"
        let truncatedDescription = Self.truncate(ekEvent.notes, maxLength: Self.maxDescriptionLength)
        let truncatedLocation = Self.truncate(ekEvent.location, maxLength: Self.maxLocationLength)
        let truncatedOrganizer = Self.truncate(ekEvent.organizer?.name, maxLength: Self.maxOrganizerLength)

        return Event(
            id: ekEvent.eventIdentifier,
            title: truncatedTitle,
            startDate: startDate,
            endDate: endDate,
            organizer: truncatedOrganizer,
            description: truncatedDescription,
            location: truncatedLocation,
            attendees: attendees,
            attachments: [],
            isAllDay: ekEvent.isAllDay,
            calendarId: ekEvent.calendar.calendarIdentifier,
            timezone: ekEvent.timeZone?.identifier ?? TimeZone.current.identifier,
            links: links,
            provider: provider,
        )
    }

    private func convertAttendee(_ participant: EKParticipant) -> Attendee? {
        // EKParticipant.url can have non-mailto schemes (e.g. tel:, sip:) which are not valid emails
        guard participant.url.scheme?.caseInsensitiveCompare("mailto") == .orderedSame else {
            return nil
        }

        let email = participant.url.absoluteString
            .replacingOccurrences(of: "mailto:", with: "", options: .caseInsensitive)

        guard !email.isEmpty else { return nil }

        let status: AttendeeStatus = switch participant.participantStatus {
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        case .pending: .needsAction
        default: .needsAction
        }

        return Attendee(
            name: participant.name,
            email: email,
            status: status,
            isOptional: participant.participantRole == .optional,
            isOrganizer: participant.participantRole == .chair,
            isSelf: participant.isCurrentUser,
        )
    }

    private func extractMeetingLinks(from ekEvent: EKEvent) -> [URL] {
        var links: [URL] = []

        // Check the event URL
        if let url = ekEvent.url {
            links.append(url)
        }

        // Check location for URLs
        if let location = ekEvent.location {
            links.append(contentsOf: extractURLs(from: location))
        }

        // Check notes for URLs
        if let notes = ekEvent.notes {
            links.append(contentsOf: extractURLs(from: notes))
        }

        // Filter to only meeting-relevant URLs using LinkParser's centralized detection
        let meetingLinks = links.filter { url in
            self.linkParser.isMeetingURL(url)
        }

        // Dedup preserving order
        var seen = Set<String>()
        return meetingLinks.filter { seen.insert($0.absoluteString.lowercased()).inserted }
    }

    private func extractURLs(from text: String) -> [URL] {
        linkParser.extractURLs(from: text)
    }

    private func sourceDescription(for calendar: EKCalendar) -> String {
        calendar.source.title
    }

    private func hexFromCGColor(_ color: CGColor) -> String? {
        guard let components = color.components, components.count >= Self.minColorComponents else { return nil }
        let redIndex = components.startIndex
        let greenIndex = components.index(after: redIndex)
        let blueIndex = components.index(after: greenIndex)
        let r = Int(components[redIndex] * Self.colorComponentScale)
        let g = Int(components[greenIndex] * Self.colorComponentScale)
        let b = Int(components[blueIndex] * Self.colorComponentScale)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
