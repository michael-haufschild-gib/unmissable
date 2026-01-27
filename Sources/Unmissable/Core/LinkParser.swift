import Foundation
import OSLog

final class LinkParser: Sendable {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "LinkParser")

    static let shared = LinkParser()

    /// Trusted domains for meeting links - only these are considered valid meeting URLs
    private static let trustedMeetingDomains = [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com",
        "webex.com",
        "gotomeeting.com",
        "whereby.com",
        "around.co",
    ]

    private init() {}

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
            in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)
        )

        for match in matches {
            guard let url = match.url else { continue }

            if isGoogleMeetURL(url) {
                meetLinks.append(url)
            }
        }

        // Remove duplicates
        return Array(Set(meetLinks))
    }

    func isGoogleMeetURL(_ url: URL) -> Bool {
        let urlString = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""

        return host.contains("meet.google.com") || urlString.contains("meet.google.com")
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

    /// Validates that a URL is from a trusted meeting domain
    /// This helps prevent phishing attacks via lookalike domains
    func isValidMeetingURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else {
            logger.debug("Rejected non-HTTPS URL: \(url.absoluteString)")
            return false
        }

        guard let host = url.host?.lowercased() else {
            logger.debug("Rejected URL with no host: \(url.absoluteString)")
            return false
        }

        // Check if host matches or is subdomain of trusted domain
        let isTrusted = Self.trustedMeetingDomains.contains { trustedDomain in
            host == trustedDomain || host.hasSuffix(".\(trustedDomain)")
        }

        if !isTrusted {
            logger.debug("Rejected untrusted domain: \(host)")
        }

        return isTrusted
    }

    // MARK: - Link Prioritization

    func detectPrimaryLink(from links: [URL]) -> URL? {
        // Filter to only validated meeting URLs
        let validLinks = links.filter { isValidMeetingURL($0) }

        // Prioritize Google Meet video links over other types (like dial-in numbers)
        if let meetLink = validLinks.first(where: { url in
            let urlString = url.absoluteString.lowercased()
            return urlString.contains("meet.google.com")
        }) {
            return meetLink
        }

        // Fallback to other validated video meeting providers
        if let videoLink = validLinks.first(where: { url in
            let urlString = url.absoluteString.lowercased()
            return urlString.contains("zoom.us") || urlString.contains("teams.microsoft.com")
                || urlString.contains("webex.com")
        }) {
            return videoLink
        }

        // Fallback to any validated link
        return validLinks.first
    }

    func isOnlineMeeting(links: [URL]) -> Bool {
        // Only consider it an online meeting if there are validated meeting links
        links.contains { isValidMeetingURL($0) }
    }
}
