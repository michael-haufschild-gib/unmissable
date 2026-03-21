import Foundation

/// Strips dangerous HTML elements that could execute code or load external resources.
/// Preserves safe formatting tags (p, a, strong, em, ul, ol, li, h1-h6, br)
/// used in calendar event descriptions.
enum HTMLSanitizer {
    /// Removes script/style/iframe/object/embed/form elements, event handler attributes,
    /// and javascript:/data: URIs from HTML content.
    static func sanitize(_ html: String) -> String {
        var sanitized = html

        // Remove entire dangerous elements and their content
        let dangerousElements = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<iframe[^>]*>[\\s\\S]*?</iframe>",
            "<object[^>]*>[\\s\\S]*?</object>",
            "<embed[^>]*>[\\s\\S]*?/?>",
            "<form[^>]*>[\\s\\S]*?</form>",
            "<link[^>]*>",
            "<meta[^>]*>",
            "<base[^>]*>",
        ]

        for pattern in dangerousElements {
            if let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]
            ) {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: NSRange(sanitized.startIndex..., in: sanitized),
                    withTemplate: ""
                )
            }
        }

        // Remove event handler attributes (onclick, onerror, onload, etc.)
        if let eventHandlerRegex = try? NSRegularExpression(
            pattern: "\\s+on\\w+\\s*=\\s*([\"'])[\\s\\S]*?\\1",
            options: [.caseInsensitive]
        ) {
            sanitized = eventHandlerRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(sanitized.startIndex..., in: sanitized),
                withTemplate: ""
            )
        }

        // Remove javascript: and data: URIs in href/src attributes
        if let jsURIRegex = try? NSRegularExpression(
            pattern: "(href|src)\\s*=\\s*([\"'])\\s*(javascript|data):",
            options: [.caseInsensitive]
        ) {
            sanitized = jsURIRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(sanitized.startIndex..., in: sanitized),
                withTemplate: "$1=$2about:blank"
            )
        }

        return sanitized
    }
}
