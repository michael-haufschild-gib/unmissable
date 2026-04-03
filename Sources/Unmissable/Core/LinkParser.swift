import Foundation
import OSLog

final class LinkParser: Sendable {
    private let logger = Logger(category: "LinkParser")

    /// Trusted domains for meeting links — only these are considered valid meeting URLs
    private static let trustedMeetingDomains = [
        "meet.google.com",
        "g.co",
        "zoom.us",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
        "gotomeeting.com",
        "whereby.com",
        "around.co",
    ]

    init() {}

    // MARK: - Google Meet Link Detection (Simplified)

    func extractGoogleMeetLinks(from text: String) -> [URL] {
        var meetLinks: [URL] = []

        // Use NSDataDetector to find URLs
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else {
            logger.error("Failed to create URL detector")
            return meetLinks
        }

        let matches = detector.matches(
            in: text, options: [], range: NSRange(location: 0, length: text.utf16.count),
        )

        for match in matches {
            guard let url = match.url else { continue }

            if isGoogleMeetURL(url) {
                meetLinks.append(url)
            }
        }

        // Stable dedup preserving insertion order
        var seen = Set<String>()
        return meetLinks.filter { seen.insert($0.absoluteString.lowercased()).inserted }
    }

    func isGoogleMeetURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        if host == "meet.google.com" || host.hasSuffix(".meet.google.com") { return true }
        if host == "g.co", url.path.lowercased().hasPrefix("/meet/") { return true }
        return false
    }

    func extractGoogleMeetID(from url: URL) -> String? {
        let path = url.path

        // Google Meet format: https://meet.google.com/abc-defg-hij
        if let lastComponent = path.components(separatedBy: "/").last,
           !lastComponent.isEmpty,
           lastComponent.contains("-")
        {
            return lastComponent
        }

        return nil
    }

    // MARK: - URL Validation

    /// Validates that a URL is from a trusted meeting domain (HTTPS only).
    /// This helps prevent phishing attacks via lookalike domains.
    func isValidMeetingURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else {
            return false
        }

        guard let host = url.host?.lowercased() else {
            return false
        }

        // g.co is a Google URL shortener — only trust /meet/ paths
        if host == "g.co" {
            return url.path.lowercased().hasPrefix("/meet/")
        }

        return Self.trustedMeetingDomains.contains { trustedDomain in
            host == trustedDomain || host.hasSuffix(".\(trustedDomain)")
        }
    }

    /// Custom URL schemes used by meeting providers (e.g., zoommtg://, msteams://, webex://).
    /// Centralized here so callers don't need to maintain their own scheme lists.
    private static let meetingURLSchemes: Set<String> = ["zoommtg", "msteams", "webex"]

    /// Checks whether a URL is a meeting link — either a trusted HTTPS domain or a known
    /// meeting app custom scheme (zoommtg://, msteams://, webex://).
    func isMeetingURL(_ url: URL) -> Bool {
        if isValidMeetingURL(url) {
            return true
        }
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return Self.meetingURLSchemes.contains(scheme)
    }

    // MARK: - Link Prioritization

    func detectPrimaryLink(from links: [URL]) -> URL? {
        let validLinks = links.filter { isMeetingURL($0) }

        // Priority 1: Google Meet (meet.google.com, g.co/meet)
        if let meetLink = validLinks.first(where: { isGoogleMeetURL($0) }) {
            return meetLink
        }

        // Priority 2: Other major video providers (exact domain matching)
        if let videoLink = validLinks.first(where: { url in
            guard let host = url.host?.lowercased() else { return false }
            return host == "zoom.us" || host.hasSuffix(".zoom.us")
                || host == "teams.microsoft.com" || host.hasSuffix(".teams.microsoft.com")
                || host == "teams.live.com" || host.hasSuffix(".teams.live.com")
                || host == "webex.com" || host.hasSuffix(".webex.com")
        }) {
            return videoLink
        }

        return validLinks.first
    }

    func isOnlineMeeting(links: [URL]) -> Bool {
        // Consider it an online meeting if there are meeting links (HTTPS domains or custom schemes)
        links.contains { isMeetingURL($0) }
    }

    // MARK: - General URL Extraction

    /// Extracts all URLs from a text string using NSDataDetector
    func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue,
        ) else {
            return []
        }
        let matches = detector.matches(
            in: text, options: [], range: NSRange(location: 0, length: text.utf16.count),
        )
        return matches.compactMap(\.url)
    }

    /// Extracts the first URL from a text string
    func extractURL(from text: String) -> URL? {
        extractURLs(from: text).first
    }

    // MARK: - Event Convenience Methods

    /// Returns the primary meeting link for the given event's links.
    func primaryLink(for event: Event) -> URL? {
        detectPrimaryLink(from: event.links)
    }

    /// Whether the event has at least one validated meeting link.
    func isOnlineMeeting(_ event: Event) -> Bool {
        isOnlineMeeting(links: event.links)
    }

    /// Join button visibility window before meeting start (seconds).
    private static let joinButtonLeadTimeSeconds: TimeInterval = 600

    /// Whether the join button should be shown for this event.
    func shouldShowJoinButton(for event: Event) -> Bool {
        guard isOnlineMeeting(event) else { return false }

        let now = Date()
        let joinWindowStart = event.startDate.addingTimeInterval(-Self.joinButtonLeadTimeSeconds)
        return now >= joinWindowStart && now < event.endDate
    }
}
