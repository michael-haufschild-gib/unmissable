import Foundation

nonisolated struct Attendee: Identifiable, Codable, Equatable {
    /// Email is unique per event in both Google Calendar API and EventKit.
    /// Using email as id preserves Equatable/Codable stability across encode/decode cycles.
    /// **Invariant:** Each Attendee in an Event.attendees array has a distinct email.
    /// The API services (Google, Apple) enforce this at fetch time.
    var id: String {
        email
    }

    let name: String?
    let email: String
    let status: AttendeeStatus?
    let isOptional: Bool
    let isOrganizer: Bool
    let isSelf: Bool

    init(
        name: String? = nil,
        email: String,
        status: AttendeeStatus? = nil,
        isOptional: Bool = false,
        isOrganizer: Bool = false,
        isSelf: Bool,
    ) {
        self.name = name
        self.email = email
        self.status = status
        self.isOptional = isOptional
        self.isOrganizer = isOrganizer
        self.isSelf = isSelf
    }

    var displayName: String {
        name ?? email
    }
}

nonisolated enum AttendeeStatus: String, Codable, CaseIterable {
    case needsAction
    case declined
    case tentative
    case accepted

    var displayText: String {
        switch self {
        case .needsAction:
            "Not responded"
        case .declined:
            "Declined"
        case .tentative:
            "Maybe"
        case .accepted:
            "Accepted"
        }
    }

    var iconName: String {
        switch self {
        case .needsAction:
            "questionmark.circle"
        case .declined:
            "xmark.circle"
        case .tentative:
            "questionmark.circle.fill"
        case .accepted:
            "checkmark.circle.fill"
        }
    }
}
