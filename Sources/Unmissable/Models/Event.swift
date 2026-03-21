import Foundation

struct Event: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let organizer: String?
    let description: String?
    let location: String?
    let attendees: [Attendee]
    let attachments: [EventAttachment]
    let isAllDay: Bool
    let calendarId: String
    let timezone: String
    let links: [URL]
    let provider: Provider?
    let snoozeUntil: Date?
    let autoJoinEnabled: Bool
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        organizer: String? = nil,
        description: String? = nil,
        location: String? = nil,
        attendees: [Attendee] = [],
        attachments: [EventAttachment] = [],
        isAllDay: Bool = false,
        calendarId: String,
        timezone: String = TimeZone.current.identifier,
        links: [URL] = [],
        provider: Provider? = nil,
        snoozeUntil: Date? = nil,
        autoJoinEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.organizer = organizer
        self.description = description
        self.location = location
        self.attendees = attendees
        self.attachments = attachments
        self.isAllDay = isAllDay
        self.calendarId = calendarId
        self.timezone = timezone
        self.links = links
        if let provider {
            self.provider = provider
        } else if links.isEmpty {
            self.provider = nil
        } else {
            self.provider = LinkParser.shared.detectPrimaryLink(from: links).map { Provider.detect(from: $0) }
        }
        self.snoozeUntil = snoozeUntil
        self.autoJoinEnabled = autoJoinEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var primaryLink: URL? {
        LinkParser.shared.detectPrimaryLink(from: links)
    }

    var isOnlineMeeting: Bool {
        LinkParser.shared.isOnlineMeeting(links: links)
    }

    var shouldShowJoinButton: Bool {
        guard isOnlineMeeting else { return false }

        let now = Date()
        let tenMinutesBeforeStart = startDate.addingTimeInterval(-600) // 10 minutes = 600 seconds

        // Show join button if:
        // 1. Meeting starts within 10 minutes (now >= tenMinutesBeforeStart AND now < startDate)
        // 2. Meeting has already started (now >= startDate AND now < endDate)
        return now >= tenMinutesBeforeStart && now < endDate
    }

    var localStartDate: Date {
        // Keep absolute instant; use DateFormatter with desired timeZone for display
        startDate
    }

    var localEndDate: Date {
        // Keep absolute instant; use DateFormatter with desired timeZone for display
        endDate
    }

    /// Creates an event by extracting Google Meet links from text fields (title, description, location).
    /// For events from calendar APIs, use the API service's conversion methods which handle all providers.
    static func withParsedMeetLinks(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        organizer: String? = nil,
        description: String? = nil,
        location: String? = nil,
        attendees: [Attendee] = [],
        attachments: [EventAttachment] = [],
        isAllDay: Bool = false,
        calendarId: String,
        timezone: String = TimeZone.current.identifier,
        snoozeUntil: Date? = nil,
        autoJoinEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> Self {
        // Combine all text fields that might contain meeting links
        let allText = [title, description, location]
            .compactMap(\.self)
            .joined(separator: " ")

        let googleMeetLinks = LinkParser.shared.extractGoogleMeetLinks(from: allText)
        let provider = googleMeetLinks.first.map { Provider.detect(from: $0) }

        return Self(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            organizer: organizer,
            description: description,
            location: location,
            attendees: attendees,
            attachments: attachments,
            isAllDay: isAllDay,
            calendarId: calendarId,
            timezone: timezone,
            links: googleMeetLinks,
            provider: provider,
            snoozeUntil: snoozeUntil,
            autoJoinEnabled: autoJoinEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
