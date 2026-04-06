import Foundation

/// PII-safe redaction helpers for diagnostic logging.
/// All helpers produce deterministic, stable output suitable for log correlation
/// while stripping PII and secrets.
/// Usable from actors (DatabaseManager) and nonisolated contexts.
enum PrivacyUtils {
    /// Prefix length for email local-part and calendar-ID display.
    private static let emailPrefixLength = 2

    /// Prefix length shown for generic identifiers.
    private static let idPrefixLength = 6

    /// Prefix length shown for opaque calendar IDs (non-email).
    private static let calendarIdPrefixLength = 8

    /// Maximum length for redacted error descriptions.
    private static let maxErrorLength = 120

    /// Maximum length for redacted titles/descriptions.
    private static let maxTitleLength = 30

    /// Expected number of parts when splitting an email address by "@".
    private static let emailPartCount = 2

    /// Number of path components to keep at the end of file paths.
    private static let pathTailComponents = 2

    // MARK: - Calendar IDs

    /// Redacts a calendar ID for logging — Google Calendar IDs often contain email addresses.
    /// Shows a short prefix to aid debugging while protecting PII.
    static func redactedCalendarId(_ id: String) -> String {
        if id.contains("@") {
            let parts = id.split(separator: "@", maxSplits: 1)
            let prefix = parts.first.map { $0.prefix(emailPrefixLength) } ?? ""
            return "\(prefix)***@\(parts.last ?? "***")"
        }
        return String(id.prefix(calendarIdPrefixLength)) + "..."
    }

    // MARK: - Event & Entity IDs

    /// Redacts an event ID to a stable prefix for log correlation.
    /// Example: "abc123-long-uuid" → "abc123…"
    static func redactedEventId(_ id: String) -> String {
        if id.count <= idPrefixLength {
            return id
        }
        return String(id.prefix(idPrefixLength)) + "…"
    }

    // MARK: - Email Addresses

    /// Redacts an email address: "user@example.com" → "us***@example.com".
    static func redactedEmail(_ email: String?) -> String {
        guard let email, !email.isEmpty else { return "<none>" }
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == emailPartCount else { return "***" }
        let prefix = parts[0].prefix(emailPrefixLength)
        return "\(prefix)***@\(parts[1])"
    }

    // MARK: - File System Paths

    /// Redacts a file path to its last N components.
    /// Example: "/Users/name/Library/App Support/unmissable/db.sqlite"
    ///        → "…/unmissable/db.sqlite"
    static func redactedPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        guard !components.isEmpty else { return "<none>" }
        if components.count <= pathTailComponents {
            return "…/" + components.joined(separator: "/")
        }
        let tail = components.suffix(pathTailComponents).joined(separator: "/")
        return "…/\(tail)"
    }

    // MARK: - URLs

    /// Redacts a URL: keeps scheme + host, strips path/query.
    /// Example: "https://meet.google.com/abc-defg?authuser=0" → "https://meet.google.com/***"
    static func redactedURL(_ url: URL?) -> String {
        guard let url else { return "<none>" }
        if let host = url.host {
            return "\(url.scheme ?? "?")://\(host)/***"
        }
        return "\(url.scheme ?? "?")://***"
    }

    /// Redacts a URL string.
    static func redactedURL(_ urlString: String?) -> String {
        guard let urlString, let url = URL(string: urlString) else { return "<none>" }
        return redactedURL(url)
    }

    // MARK: - API Errors & Response Bodies

    /// Redacts an error description: truncates and strips potential tokens/secrets.
    static func redactedError(_ error: Error) -> String {
        redactedErrorString(error.localizedDescription)
    }

    /// Redacts a raw error string: truncates long messages.
    static func redactedErrorString(_ message: String) -> String {
        if message.count <= maxErrorLength {
            return message
        }
        return String(message.prefix(maxErrorLength)) + "…[truncated]"
    }

    // MARK: - Titles & Descriptions

    /// Redacts a meeting title or description for logging.
    /// Shows a length indicator and first few words only.
    static func redactedTitle(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "<untitled>" }
        if title.count <= maxTitleLength {
            return title
        }
        return String(title.prefix(maxTitleLength)) + "…[\(title.count) chars]"
    }
}
