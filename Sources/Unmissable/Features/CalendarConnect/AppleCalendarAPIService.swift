import EventKit
import Foundation
import OSLog

/// Fetches calendars and events from macOS Calendar via EventKit.
/// Supports iCloud, Exchange, CalDAV, and any other source configured in System Settings.
@MainActor
final class AppleCalendarAPIService: ObservableObject, CalendarAPIProviding {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "AppleCalendarAPI")
    private let eventStore: EKEventStore

    @Published
    var calendars: [CalendarInfo] = []
    @Published
    var events: [Event] = []
    @Published
    var lastError: String?

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func fetchCalendars() async {
        logger.debug("Fetching Apple Calendar list")
        lastError = nil

        let ekCalendars = eventStore.calendars(for: .event)
        calendars = ekCalendars.map { convertToCalendarInfo($0) }

        logger.debug("Fetched \(self.calendars.count) Apple calendars")
    }

    func fetchEvents(for calendarIds: [String], from startDate: Date, to endDate: Date) async {
        logger.debug("Fetching Apple Calendar events for \(calendarIds.count) calendars")
        lastError = nil

        let ekCalendars = eventStore.calendars(for: .event).filter { calendarIds.contains($0.calendarIdentifier) }

        guard !ekCalendars.isEmpty else {
            logger.warning("No matching Apple calendars found for provided IDs")
            events = []
            return
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: ekCalendars
        )

        let ekEvents = eventStore.events(matching: predicate)

        events = ekEvents.compactMap { convertToEvent($0) }
            .sorted { $0.startDate < $1.startDate }

        logger.debug("Fetched \(self.events.count) Apple Calendar events")
    }

    // MARK: - Conversion

    private func convertToCalendarInfo(_ ekCalendar: EKCalendar) -> CalendarInfo {
        CalendarInfo(
            id: ekCalendar.calendarIdentifier,
            name: ekCalendar.title,
            description: sourceDescription(for: ekCalendar),
            isSelected: false,
            isPrimary: ekCalendar.calendarIdentifier == eventStore.defaultCalendarForNewEvents?.calendarIdentifier,
            colorHex: ekCalendar.cgColor.flatMap { hexFromCGColor($0) },
            sourceProvider: .apple
        )
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
        let provider = links.first.map { Provider.detect(from: $0) }

        return Event(
            id: ekEvent.eventIdentifier,
            title: ekEvent.title ?? "Untitled Event",
            startDate: startDate,
            endDate: endDate,
            organizer: ekEvent.organizer?.name,
            description: ekEvent.notes,
            location: ekEvent.location,
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

        // Filter to only meeting-relevant URLs
        let meetingDomains = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com"]
        let meetingLinks = links.filter { url in
            let host = url.host?.lowercased() ?? ""
            return meetingDomains.contains(where: { host.contains($0) })
                || url.scheme == "zoommtg"
                || url.scheme == "msteams"
                || url.scheme == "webex"
        }

        // Dedup preserving order
        var seen = Set<String>()
        return meetingLinks.filter { seen.insert($0.absoluteString.lowercased()).inserted }
    }

    private func extractURLs(from text: String) -> [URL] {
        LinkParser.shared.extractURLs(from: text)
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
