import Foundation

struct Attendee: Identifiable, Codable, Equatable, Sendable {
    /// Email is unique and stable, making it a reliable identifier across encode/decode cycles
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
        isSelf: Bool
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

enum AttendeeStatus: String, Codable, CaseIterable, Sendable {
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
