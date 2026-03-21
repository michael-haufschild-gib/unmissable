import Foundation

/// Strips dangerous HTML elements that could execute code or load external resources.
/// Preserves safe formatting tags (p, a, strong, em, ul, ol, li, h1-h6, br)
/// used in calendar event descriptions.
enum HTMLSanitizer {
    // MARK: - Cached Regex Patterns

    /// Compiled patterns for dangerous HTML elements to strip entirely.
    private static let dangerousElementPatterns: [NSRegularExpression] = [
        "<script[^>]*>[\\s\\S]*?</script>",
        "<style[^>]*>[\\s\\S]*?</style>",
        "<iframe[^>]*>[\\s\\S]*?</iframe>",
        "<object[^>]*>[\\s\\S]*?</object>",
        "<embed[^>]*>[\\s\\S]*?/?>",
        "<form[^>]*>[\\s\\S]*?</form>",
        "<link[^>]*>",
        "<meta[^>]*>",
        "<base[^>]*>",
    ].map { pattern in
        // Force-unwrap is intentional: these are compile-time-known literals.
        // A crash here means a developer introduced an invalid pattern.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Matches event handler attributes (onclick, onerror, onload, etc.)
    // swiftlint:disable:next force_try
    private static let eventHandlerPattern = try! NSRegularExpression(
        pattern: "\\s+on\\w+\\s*=\\s*([\"'])[\\s\\S]*?\\1",
        options: [.caseInsensitive]
    )

    /// Matches javascript: and data: URIs in href/src attributes (through closing quote)
    // swiftlint:disable:next force_try
    private static let jsURIPattern = try! NSRegularExpression(
        pattern: "(href|src)\\s*=\\s*([\"'])\\s*(javascript|data):[^\"']*\\2",
        options: [.caseInsensitive]
    )

    /// Removes script/style/iframe/object/embed/form elements, event handler attributes,
    /// and javascript:/data: URIs from HTML content.
    static func sanitize(_ html: String) -> String {
        var sanitized = html

        // Remove entire dangerous elements and their content
        for regex in dangerousElementPatterns {
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(sanitized.startIndex..., in: sanitized),
                withTemplate: ""
            )
        }

        // Remove event handler attributes (onclick, onerror, onload, etc.)
        sanitized = eventHandlerPattern.stringByReplacingMatches(
            in: sanitized,
            range: NSRange(sanitized.startIndex..., in: sanitized),
            withTemplate: ""
        )

        // Remove javascript: and data: URIs in href/src attributes
        sanitized = jsURIPattern.stringByReplacingMatches(
            in: sanitized,
            range: NSRange(sanitized.startIndex..., in: sanitized),
            withTemplate: "$1=$2about:blank$2"
        )

        return sanitized
    }
}
