import OSLog

extension Logger {
    /// Shared subsystem identifier for all Unmissable loggers.
    /// Matches the app's bundle identifier so Console.app filtering works correctly.
    nonisolated static let subsystemID = "com.unmissable.app"

    /// Convenience initializer using the shared subsystem.
    nonisolated init(category: String) {
        self.init(subsystem: Self.subsystemID, category: category)
    }
}

// MARK: - Privacy Utilities

/// Redacts a calendar ID for logging — Google Calendar IDs often contain email addresses.
/// Shows a short prefix to aid debugging while protecting PII.
nonisolated enum PrivacyUtils {
    private static let redactedPrefixLength = 2
    private static let redactedIdLength = 8

    static func redactedCalendarId(_ id: String) -> String {
        if id.contains("@") {
            let parts = id.split(separator: "@", maxSplits: 1)
            let prefix = parts.first.map { $0.prefix(redactedPrefixLength) } ?? ""
            return "\(prefix)***@\(parts.last ?? "***")"
        }
        return String(id.prefix(redactedIdLength)) + "..."
    }
}
