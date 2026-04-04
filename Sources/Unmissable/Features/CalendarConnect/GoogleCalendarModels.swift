import Foundation

// MARK: - Google Calendar API Codable Response Models

// These models mirror the Google Calendar API JSON schema where fields are genuinely optional.
// swiftlint:disable discouraged_optional_collection discouraged_optional_boolean

/// Top-level response for calendar list endpoint
nonisolated struct GCalCalendarListResponse: Codable {
    let items: [GCalCalendarEntry]?
}

nonisolated struct GCalCalendarEntry: Codable {
    let id: String
    let summary: String?
    let description: String?
    let primary: Bool?
    let colorId: String?

    /// Maps Google Calendar's numeric colorId to the actual hex color.
    /// Palette from https://developers.google.com/calendar/api/v3/reference/colors/get
    var colorHex: String? {
        guard let colorId else { return nil }
        return Self.calendarColorPalette[colorId]
    }

    private static let calendarColorPalette: [String: String] = [
        "1": "#795548", // Cocoa
        "2": "#33B679", // Sage
        "3": "#8E24AA", // Grape
        "4": "#E67C73", // Flamingo
        "5": "#F6BF26", // Banana
        "6": "#F4511E", // Tangerine
        "7": "#039BE5", // Peacock
        "8": "#616161", // Graphite
        "9": "#3F51B5", // Blueberry
        "10": "#0B8043", // Basil
        "11": "#D50000", // Tomato
        "12": "#F09300", // Pumpkin
        "13": "#009688", // Avocado
        "14": "#7986CB", // Lavender
        "15": "#CD74E6", // Wisteria
        "16": "#4285F4", // Cobalt
        "17": "#A79B8E", // Birch
        "18": "#AD1457", // Radicchio
        "19": "#D81B60", // Cherry Blossom
        "20": "#EF6C00", // Mango
        "21": "#C0CA33", // Pistachio
        "22": "#009688", // Eucalyptus
        "23": "#4285F4", // Lapis Lazuli
        "24": "#795548", // Clay
    ]
}

/// Top-level response for events list endpoint
nonisolated struct GCalEventListResponse: Codable {
    let items: [GCalEventEntry]?
    let nextPageToken: String?
}

nonisolated struct GCalEventEntry: Codable, Equatable {
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

nonisolated struct GCalDateTime: Codable, Equatable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}

nonisolated struct GCalOrganizer: Codable, Equatable {
    let email: String?
}

nonisolated struct GCalAttendee: Codable, Equatable {
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

nonisolated struct GCalAttachment: Codable, Equatable {
    let fileUrl: String?
    let title: String?
    let mimeType: String?
    let iconLink: String?
    let fileId: String?
}

nonisolated struct GCalConferenceData: Codable, Equatable {
    let entryPoints: [GCalEntryPoint]?
}

nonisolated struct GCalEntryPoint: Codable, Equatable {
    let uri: String?
    let entryPointType: String?
}

// swiftlint:enable discouraged_optional_collection discouraged_optional_boolean
