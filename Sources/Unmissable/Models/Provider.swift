import Foundation

enum Provider: String, Codable, CaseIterable, Sendable {
  case meet = "meet"
  case zoom = "zoom"
  case teams = "teams"
  case webex = "webex"
  case generic = "generic"

  var displayName: String {
    switch self {
    case .meet:
      return "Google Meet"
    case .zoom:
      return "Zoom"
    case .teams:
      return "Microsoft Teams"
    case .webex:
      return "Cisco Webex"
    case .generic:
      return "Other"
    }
  }

  var iconName: String {
    switch self {
    case .meet:
      return "video.fill"
    case .zoom:
      return "video.fill"
    case .teams:
      return "video.fill"
    case .webex:
      return "video.fill"
    case .generic:
      return "link"
    }
  }

  var urlSchemes: [String] {
    switch self {
    case .meet:
      return ["https://meet.google.com", "https://g.co/meet"]
    case .zoom:
      return ["https://zoom.us", "zoommtg://"]
    case .teams:
      return ["https://teams.microsoft.com", "https://teams.live.com", "msteams://"]
    case .webex:
      return ["https://webex.com", "webex://"]
    case .generic:
      return ["https://", "http://"]
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
