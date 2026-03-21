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
        sanitized = sanitized.replacing(#/<script[^>]*>[\s\S]*?<\/script>/#.ignoresCase(), with: "")
        sanitized = sanitized.replacing(#/<style[^>]*>[\s\S]*?<\/style>/#.ignoresCase(), with: "")
        sanitized = sanitized.replacing(#/<iframe[^>]*>[\s\S]*?<\/iframe>/#.ignoresCase(), with: "")
        sanitized = sanitized.replacing(#/<object[^>]*>[\s\S]*?<\/object>/#.ignoresCase(), with: "")
        sanitized = sanitized.replacing(#/<embed[^>]*>[\s\S]*?\/?>/# .ignoresCase(), with: "")
        sanitized = sanitized.replacing(#/<form[^>]*>[\s\S]*?<\/form>/#.ignoresCase(), with: "")
        sanitized = sanitized.replacing(#/<link[^>]*>/#.ignoresCase(), with: "")
        sanitized = sanitized.replacing(#/<meta[^>]*>/#.ignoresCase(), with: "")
        sanitized = sanitized.replacing(#/<base[^>]*>/#.ignoresCase(), with: "")

        // Remove event handler attributes (onclick, onerror, onload, etc.)
        sanitized = sanitized.replacing(
            #/\s+on\w+\s*=\s*(["'])[\s\S]*?\1/#.ignoresCase(),
            with: ""
        )

        // Remove javascript: and data: URIs in href/src attributes
        sanitized = sanitized.replacing(
            #/(href|src)\s*=\s*(["'])\s*(javascript|data):[^"']*\2/#.ignoresCase()
        ) { match in
            "\(match.output.1)=\(match.output.2)about:blank\(match.output.2)"
        }

        return sanitized
    }
}
