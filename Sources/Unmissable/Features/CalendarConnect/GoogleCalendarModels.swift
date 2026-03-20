import Foundation

// MARK: - Google Calendar API Codable Response Models

// These models mirror the Google Calendar API JSON schema where fields are genuinely optional.
// swiftlint:disable discouraged_optional_collection discouraged_optional_boolean

/// Top-level response for calendar list endpoint
struct GCalCalendarListResponse: Codable {
    let items: [GCalCalendarEntry]?
}

struct GCalCalendarEntry: Codable {
    let id: String
    let summary: String?
    let description: String?
    let primary: Bool?
    let colorId: String?
}

/// Top-level response for events list endpoint
struct GCalEventListResponse: Codable {
    let items: [GCalEventEntry]?
    let nextPageToken: String?
}

struct GCalEventEntry: Codable {
    let id: String?
    let summary: String?
    let status: String?
    let start: GCalDateTime?
    let end: GCalDateTime?
    let organizer: GCalOrganizer?
    let description: String?
    let location: String?
    let attendees: [GCalAttendee]?
    let attachments: [GCalAttachment]?
    let conferenceData: GCalConferenceData?
    let hangoutLink: String?
}

struct GCalDateTime: Codable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}

struct GCalOrganizer: Codable {
    let email: String?
}

struct GCalAttendee: Codable {
    let email: String?
    let displayName: String?
    let responseStatus: String?
    let isOptional: Bool?
    let isOrganizer: Bool?
    let isSelf: Bool?

    private enum CodingKeys: String, CodingKey {
        case email, displayName, responseStatus
        case isOptional = "optional"
        case isOrganizer = "organizer"
        case isSelf = "self"
    }
}

struct GCalAttachment: Codable {
    let fileUrl: String?
    let title: String?
    let mimeType: String?
    let iconLink: String?
    let fileId: String?
}

struct GCalConferenceData: Codable {
    let entryPoints: [GCalEntryPoint]?
}

struct GCalEntryPoint: Codable {
    let uri: String?
    let entryPointType: String?
}

// swiftlint:enable discouraged_optional_collection discouraged_optional_boolean
