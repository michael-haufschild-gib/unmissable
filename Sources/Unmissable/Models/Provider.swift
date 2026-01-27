import Foundation

enum Provider: String, Codable, CaseIterable, Sendable {
    case meet
    case zoom
    case teams
    case webex
    case generic

    var displayName: String {
        switch self {
        case .meet:
            "Google Meet"
        case .zoom:
            "Zoom"
        case .teams:
            "Microsoft Teams"
        case .webex:
            "Cisco Webex"
        case .generic:
            "Other"
        }
    }

    var iconName: String {
        switch self {
        case .meet:
            "video.fill"
        case .zoom:
            "video.fill"
        case .teams:
            "video.fill"
        case .webex:
            "video.fill"
        case .generic:
            "link"
        }
    }

    var urlSchemes: [String] {
        switch self {
        case .meet:
            ["https://meet.google.com", "https://g.co/meet"]
        case .zoom:
            ["https://zoom.us", "zoommtg://"]
        case .teams:
            ["https://teams.microsoft.com", "https://teams.live.com", "msteams://"]
        case .webex:
            ["https://webex.com", "webex://"]
        case .generic:
            ["https://", "http://"]
        }
    }

    static func detect(from url: URL) -> Provider {
        let urlString = url.absoluteString.lowercased()

        if urlString.contains("meet.google.com") || urlString.contains("g.co/meet") {
            return .meet
        } else if urlString.contains("zoom.us") || urlString.hasPrefix("zoommtg://") {
            return .zoom
        } else if urlString.contains("teams.microsoft.com") || urlString.contains("teams.live.com")
            || urlString.hasPrefix("msteams://")
        {
            return .teams
        } else if urlString.contains("webex.com") || urlString.hasPrefix("webex://") {
            return .webex
        } else {
            return .generic
        }
    }
}
