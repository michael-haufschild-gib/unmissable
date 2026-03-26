import Foundation

enum GoogleCalendarConfig {
    // OAuth 2.0 configuration for Google Calendar API
    // Static URL constants — these are hardcoded valid URLs that cannot fail to parse.
    // Force unwrap is correct here; suppressing the lint rule for compile-time constant URLs.
    // swiftlint:disable force_unwrapping
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let issuer = URL(string: "https://accounts.google.com")!
    // swiftlint:enable force_unwrapping

    /// Google Calendar API scopes
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
        "https://www.googleapis.com/auth/userinfo.email",
    ]

    // MARK: - Secure Configuration Loading

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

        // Deterministic fallback matching the bundle ID
        return "com.unmissable.app"
    }()

    static let redirectURI = "\(redirectScheme):/"

    /// API Base URLs
    static let calendarAPIBaseURL = "https://www.googleapis.com/calendar/v3"

    // MARK: - Sandbox Detection

    /// Whether the app is running in a sandboxed environment
    private static let isSandboxed: Bool = {
        let environment = ProcessInfo.processInfo.environment
        // Sandboxed apps have APP_SANDBOX_CONTAINER_ID set
        return environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }()

    // MARK: - Configuration Loading Helper

    // Loads Config.plist from app bundle Resources or project root directory.
    // Handles both bundled app and development contexts.
    // swiftlint:disable:next discouraged_optional_collection - config file may not exist
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
}
