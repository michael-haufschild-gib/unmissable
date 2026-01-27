import Foundation

struct Event: Identifiable, Codable, Equatable, Sendable {
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
    self.provider = provider ?? (links.first.map { Provider.detect(from: $0) })
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
    let tenMinutesBeforeStart = startDate.addingTimeInterval(-600)  // 10 minutes = 600 seconds

    // Show join button if:
    // 1. Meeting starts within 10 minutes (now >= tenMinutesBeforeStart AND now < startDate)
    // 2. Meeting has already started (now >= startDate AND now < endDate)
    return now >= tenMinutesBeforeStart && now < endDate
  }

  var localStartDate: Date {
    // Keep absolute instant; use DateFormatter with desired timeZone for display
    return startDate
  }

  var localEndDate: Date {
    // Keep absolute instant; use DateFormatter with desired timeZone for display
    return endDate
  }

  // Helper method to create event with parsed Google Meet links
  static func withParsedLinks(
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
  ) -> Event {
    // Combine all text fields that might contain meeting links
    let allText = [title, description, location]
      .compactMap { $0 }
      .joined(separator: " ")

    let googleMeetLinks = LinkParser.shared.extractGoogleMeetLinks(from: allText)
    let provider = googleMeetLinks.first.map { Provider.detect(from: $0) }

    return Event(
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
