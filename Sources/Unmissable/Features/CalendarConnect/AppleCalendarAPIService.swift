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
    func fetchCalendars() async -> [CalendarInfo] {
        logger.debug("Fetching Apple Calendar list")
        lastError = nil

        let ekCalendars = eventStore.calendars(for: .event)
        calendars = ekCalendars.map { convertToCalendarInfo($0) }

        logger.debug("Fetched \(self.calendars.count) Apple calendars")
        return calendars
    }

    @discardableResult
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
            calendars: ekCalendars
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
            sourceProvider: .apple
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
        let truncatedTitle = Self.truncate(ekEvent.title, maxLength: 500) ?? "Untitled Event"
        let truncatedDescription = Self.truncate(ekEvent.notes, maxLength: 10_000)
        let truncatedLocation = Self.truncate(ekEvent.location, maxLength: 1000)
        let truncatedOrganizer = Self.truncate(ekEvent.organizer?.name, maxLength: 320)

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
            provider: provider
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
            isSelf: participant.isCurrentUser
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
        guard let components = color.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
