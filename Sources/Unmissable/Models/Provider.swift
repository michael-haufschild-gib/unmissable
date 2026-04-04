import Foundation

enum Provider: String, Codable, CaseIterable {
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
        self == .generic ? "link" : "video.fill"
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

    /// Bundle identifiers of native macOS apps for this provider.
    /// Used by smart alert suppression to detect if the meeting app is already in the foreground.
    /// Returns an empty array for browser-based providers (Google Meet) and unknown providers.
    var knownBundleIdentifiers: [String] {
        switch self {
        case .meet:
            []
        case .zoom:
            ["us.zoom.xos"]
        case .teams:
            ["com.microsoft.teams", "com.microsoft.teams2"]
        case .webex:
            ["com.webex.meetingmanager", "com.cisco.webexmeetings"]
        case .generic:
            []
        }
    }

    /// Classifies a URL as a specific meeting provider.
    /// Uses host-based matching for the top-4 providers. Additional services
    /// in `LinkParser.trustedMeetingDomains` (Jitsi, BlueJeans, Skype, etc.)
    /// map to `.generic`. If you add a provider case here, update LinkParser too.
    static func detect(from url: URL) -> Self {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""

        // Custom URL schemes for native meeting apps
        switch scheme {
        case "zoommtg": return .zoom
        case "msteams": return .teams
        case "webex": return .webex
        default: break
        }

        // HTTPS domain matching
        if host == "meet.google.com" || host.hasSuffix(".meet.google.com") {
            return .meet
        }
        if host == "g.co", url.path.lowercased().hasPrefix("/meet/") {
            return .meet
        }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return .zoom
        }
        if host == "teams.microsoft.com" || host.hasSuffix(".teams.microsoft.com")
            || host == "teams.live.com" || host.hasSuffix(".teams.live.com")
        {
            return .teams
        }
        if host == "webex.com" || host.hasSuffix(".webex.com") {
            return .webex
        }
        return .generic
    }
}
