import Foundation

struct GoogleCalendarConfig {
  // OAuth 2.0 configuration for Google Calendar API
  static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
  static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
  static let issuer = URL(string: "https://accounts.google.com")!

  // Google Calendar API scopes
  static let scopes = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    "https://www.googleapis.com/auth/userinfo.email",
  ]

  // MARK: - Secure Configuration Loading

  /// Error message if OAuth is not configured
  static let configurationError: String? = {
    if clientId.isEmpty {
      return """
        OAuth Client ID not configured.

        Setup options:
        1. Set GOOGLE_OAUTH_CLIENT_ID environment variable
        2. Add GoogleOAuthClientID to Config.plist in project root

        Get credentials at: https://console.developers.google.com/
        """
    }
    return nil
  }()

  /// Whether OAuth is properly configured
  static var isConfigured: Bool {
    !clientId.isEmpty
  }

  /// OAuth Client ID - loads from environment variable or Config.plist (in project root)
  /// This prevents committing sensitive credentials to git
  /// Returns empty string if not configured (check isConfigured before use)
  static let clientId: String = {
    // Try environment variable first (for development/CI)
    if let envClientId = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"],
      !envClientId.isEmpty,
      !envClientId.contains("YOUR_GOOGLE_OAUTH_CLIENT_ID")
    {
      return envClientId
    }

    // Try loading from Config.plist in project root (for VS Code/SPM development)
    if let configData = loadConfigFromProjectRoot(),
      let clientId = configData["GoogleOAuthClientID"] as? String,
      !clientId.isEmpty,
      !clientId.contains("YOUR_GOOGLE_OAUTH_CLIENT_ID")
    {
      return clientId
    }

    // Return empty string instead of crashing - allows app to start and show configuration UI
    return ""
  }()

  static let redirectScheme: String = {
    // Try environment variable first
    if let envScheme = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_REDIRECT_SCHEME"],
      !envScheme.isEmpty
    {
      return envScheme
    }

    // Try Config.plist in project root
    if let configData = loadConfigFromProjectRoot(),
      let scheme = configData["RedirectScheme"] as? String,
      !scheme.isEmpty
    {
      return scheme
    }

    // Safe default fallback - use unique scheme with bundle identifier hash to prevent hijacking
    let bundleHash = abs(Bundle.main.bundleIdentifier?.hashValue ?? 0)
    return "com.unmissable.oauth.\(bundleHash)"
  }()

  static let redirectURI = "\(redirectScheme):/"

  // API Base URLs
  static let calendarAPIBaseURL = "https://www.googleapis.com/calendar/v3"

  // MARK: - Environment Detection

  static let environment: String = {
    return ProcessInfo.processInfo.environment["UNMISSABLE_ENV"] ?? "production"
  }()

  static var isDevelopment: Bool {
    return environment == "development"
  }

  // MARK: - Sandbox Detection

  /// Whether the app is running in a sandboxed environment
  private static let isSandboxed: Bool = {
    let environment = ProcessInfo.processInfo.environment
    // Sandboxed apps have APP_SANDBOX_CONTAINER_ID set
    return environment["APP_SANDBOX_CONTAINER_ID"] != nil
  }()

  // MARK: - Configuration Loading Helper

  /// Loads Config.plist from app bundle Resources or project root directory
  /// Handles both bundled app and development contexts
  private static func loadConfigFromProjectRoot() -> [String: Any]? {
    // First, try to load from app bundle Resources (for bundled app / App Store)
    if let bundlePath = Bundle.main.path(forResource: "Config", ofType: "plist"),
      let plist = NSDictionary(contentsOfFile: bundlePath) as? [String: Any]
    {
      return plist
    }

    // In sandbox mode, we can ONLY use bundle resources - don't try filesystem paths
    if isSandboxed {
      return nil
    }

    // For VS Code + SPM development (non-sandboxed), try current working directory
    let currentDir = FileManager.default.currentDirectoryPath
    let configPath = NSString(string: currentDir).appendingPathComponent("Config.plist")

    if FileManager.default.fileExists(atPath: configPath),
      let plist = NSDictionary(contentsOfFile: configPath) as? [String: Any]
    {
      return plist
    }

    // Fallback paths for different build contexts (non-sandboxed only)
    let possiblePaths = [
      "Config.plist",  // Direct in working directory
      "../Config.plist",  // One level up
      "../../Config.plist",  // Two levels up (for .build directory)
      "../../../Config.plist",  // Three levels up
    ]

    for relativePath in possiblePaths {
      let expandedPath = NSString(string: relativePath).expandingTildeInPath
      if FileManager.default.fileExists(atPath: expandedPath),
        let plist = NSDictionary(contentsOfFile: expandedPath) as? [String: Any]
      {
        return plist
      }
    }

    return nil
  }
}

extension GoogleCalendarConfig {
  /// Validates that the OAuth configuration is properly set up
  static func validateConfiguration() -> Bool {
    // Check if client ID is configured (no longer crashes)
    guard !clientId.isEmpty else {
      return false
    }
    guard !redirectScheme.isEmpty else {
      return false
    }
    return true
  }

  /// Returns configuration status for debugging
  static func configurationStatus() -> String {
    return """
      📊 OAUTH CONFIGURATION STATUS:
      • Client ID: \(clientId.isEmpty ? "❌ Missing" : "✅ Configured (\(clientId.prefix(20))...)")
      • Redirect Scheme: \(redirectScheme)
      • Environment: \(environment)
      • Configuration Source: \(configurationSource())
      • Scopes: \(scopes.count) configured
      """
  }

  private static func configurationSource() -> String {
    if ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"] != nil {
      return "Environment Variable"
    } else if Bundle.main.path(forResource: "Config", ofType: "plist") != nil {
      return "App Bundle Resources"
    } else if loadConfigFromProjectRoot() != nil {
      return "Config.plist (project root)"
    } else {
      return "Default/Fallback"
    }
  }

  /// Whether the app is running sandboxed (exposed for debugging)
  static var isSandboxedEnvironment: Bool {
    isSandboxed
  }
}
