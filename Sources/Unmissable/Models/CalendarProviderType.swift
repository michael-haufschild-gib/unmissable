import Foundation

/// Identifies which calendar backend provided a calendar or event.
enum CalendarProviderType: String, Codable, CaseIterable {
    case google
    case apple

    var displayName: String {
        switch self {
        case .google:
            "Google Calendar"
        case .apple:
            "Apple Calendar"
        }
    }

    var iconName: String {
        switch self {
        case .google:
            "calendar"
        case .apple:
            "apple.logo"
        }
    }

    var connectionLabel: String {
        switch self {
        case .google:
            "Connect Google Calendar"
        case .apple:
            "Connect Apple Calendar"
        }
    }
}
