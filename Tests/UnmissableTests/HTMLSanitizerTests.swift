import Foundation
import Testing
@testable import Unmissable

struct HTMLSanitizerTests {
    // MARK: - Dangerous Element Removal

    @Test
    func stripsScriptTags() {
        let input = "<p>Hello</p><script>alert('xss')</script><p>World</p>"
        let result = HTMLSanitizer.sanitize(input)

        #expect(result == "<p>Hello</p><p>World</p>")
    }

    @Test
    func stripsScriptTagsCaseInsensitive() {
        let input = "<SCRIPT>alert('xss')</SCRIPT>"
        let result = HTMLSanitizer.sanitize(input)

        #expect(result.isEmpty)
    }

    @Test
    func stripsIframeTags() {
        let input = "<p>Meeting notes</p><iframe src=\"https://evil.com\"></iframe>"
        let result = HTMLSanitizer.sanitize(input)

        #expect(result == "<p>Meeting notes</p>")
    }

    @Test
    func stripsStyleTags() {
        let input = "<style>body { background: url('https://tracking.com') }</style><p>Content</p>"
        let result = HTMLSanitizer.sanitize(input)

        #expect(result == "<p>Content</p>")
    }

    @Test
    func stripsObjectAndEmbedTags() {
        let input = "<object data=\"evil.swf\"></object><embed src=\"evil.swf\"/>"
        let result = HTMLSanitizer.sanitize(input)

        #expect(result.isEmpty)
    }

    @Test
    func stripsFormTags() {
        let input = "<form action=\"https://evil.com\"><input type=\"text\"></form>"
        let result = HTMLSanitizer.sanitize(input)

        // input tag without form is harmless rendered text
        #expect(!result.contains("form"))
        #expect(!result.contains("evil.com"))
    }

    @Test
    func stripsLinkMetaBaseTags() {
        let input =
            "<link rel=\"stylesheet\" href=\"evil.css\"><meta http-equiv=\"refresh\"><base href=\"evil\">"
        let result = HTMLSanitizer.sanitize(input)

        #expect(result.isEmpty)
    }

    // MARK: - Event Handler Removal

    @Test
    func stripsOnclickHandlers() {
        let input = "<a href=\"https://meet.google.com\" onclick=\"steal()\">Join</a>"
        let result = HTMLSanitizer.sanitize(input)

        #expect(!result.contains("onclick"))
        #expect(!result.contains("steal"))
        #expect(result == "<a href=\"https://meet.google.com\">Join</a>")
    }

    @Test
    func stripsOnerrorHandlers() {
        let input = "<img src=\"x\" onerror=\"alert(1)\">"
        let result = HTMLSanitizer.sanitize(input)

        #expect(!result.contains("onerror"))
        #expect(!result.contains("alert"))
    }

    @Test
    func stripsOnloadHandlers() {
        let input = "<body onload=\"malicious()\">"
        let result = HTMLSanitizer.sanitize(input)

        #expect(!result.contains("onload"))
        #expect(!result.contains("malicious"))
    }

    // MARK: - JavaScript URI Neutralization

    @Test
    func neutralizesJavascriptURIs() {
        let input = "<a href=\"javascript:alert(document.cookie)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)

        #expect(!result.contains("javascript:"))
        #expect(result == "<a href=\"about:blank\">Click</a>")
    }

    @Test
    func neutralizesDataURIs() {
        let input = "<img src=\"data:text/html,<script>alert(1)</script>\">"
        let result = HTMLSanitizer.sanitize(input)

        #expect(!result.lowercased().contains("data:text"))
    }

    // MARK: - Safe Content Preservation

    @Test
    func preservesSafeFormattingTags() {
        let input = "<p><strong>Bold</strong> and <em>italic</em></p>"
        #expect(HTMLSanitizer.sanitize(input) == input)
    }

    @Test
    func preservesLists() {
        let input = "<ul><li>Item 1</li><li>Item 2</li></ul>"
        #expect(HTMLSanitizer.sanitize(input) == input)
    }

    @Test
    func preservesHeadings() {
        let input = "<h1>Title</h1><h2>Subtitle</h2>"
        #expect(HTMLSanitizer.sanitize(input) == input)
    }

    @Test
    func preservesSafeLinks() {
        let input = "<a href=\"https://meet.google.com/abc-def\">Join Meeting</a>"
        #expect(HTMLSanitizer.sanitize(input) == input)
    }

    @Test
    func preservesLineBreaks() {
        let input = "Line 1<br>Line 2<br/>Line 3"
        #expect(HTMLSanitizer.sanitize(input) == input)
    }

    // MARK: - Edge Cases

    @Test
    func handlesEmptyString() {
        #expect(HTMLSanitizer.sanitize("").isEmpty)
    }

    @Test
    func handlesPlainText() {
        let input = "Just plain text with no HTML"
        #expect(HTMLSanitizer.sanitize(input) == input)
    }

    @Test
    func handlesUnclosedTag() {
        // An unclosed tag (no >) should be treated as literal text
        let input = "<p>Hello <strong"
        let result = HTMLSanitizer.sanitize(input)
        // The tokenizer should handle this without crashing
        #expect(result.contains("Hello"))
    }

    @Test
    func handlesUnclosedDangerousTag() {
        // Script tag that never closes
        let input = "<script>alert('xss')"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            !result.contains("alert"),
            "Script content should be removed even without closing tag",
        )
    }

    @Test
    func stripsDataURIWithBase64() {
        let input = "<img src=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==\">"
        let result = HTMLSanitizer.sanitize(input)
        #expect(!result.lowercased().contains("data:"))
    }

    @Test
    func neutralizesJavascriptURIWithWhitespace() {
        let input = "<a href=\"  javascript:alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            !result.contains("javascript:"),
            "Leading whitespace should not bypass javascript: detection",
        )
        #expect(result.contains("about:blank"))
    }

    @Test
    func neutralizesEntityEncodedJavascriptURI() {
        let input = "<a href=\"&#106;avascript:alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(result.contains("about:blank"), "Entity-encoded javascript: should be neutralized")
        #expect(!result.contains("alert"), "Payload must not appear in output")
    }

    @Test
    func neutralizesHexEntityEncodedJavascriptURI() {
        let input = "<a href=\"&#x6A;avascript:alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            result.contains("about:blank"),
            "Hex entity-encoded javascript: should be neutralized",
        )
        #expect(!result.contains("alert"), "Payload must not appear in output")
    }

    @Test
    func neutralizesInlineControlCharJavascriptURI() {
        // Browsers may interpret "java\nscript:" as "javascript:" — control chars within
        // the scheme must be stripped before the prefix check.
        let newlineBypass = "<a href=\"java&#x0A;script:alert(1)\">Click</a>"
        let tabBypass = "<a href=\"jav&#9;ascript:alert(1)\">Click</a>"
        #expect(
            HTMLSanitizer.sanitize(newlineBypass).contains("about:blank"),
            "Newline-in-scheme javascript: bypass should be neutralized",
        )
        #expect(
            HTMLSanitizer.sanitize(tabBypass).contains("about:blank"),
            "Tab-in-scheme javascript: bypass should be neutralized",
        )
    }

    @Test
    func neutralizesEntityEncodedDataURI() {
        let input = "<img src=\"&#100;ata:text/html,<script>alert(1)</script>\">"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            result.contains("about:blank"),
            "Entity-encoded data: should be neutralized to about:blank",
        )
        #expect(!result.contains("alert"), "Payload must not appear in output")
        #expect(!result.contains("script"), "Script tag must not appear in output")
    }

    @Test
    func neutralizesColonEntityJavascriptURI() {
        let input = "<a href=\"javascript&colon;alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            result.contains("about:blank"),
            "&colon; entity should be decoded before scheme check",
        )
        #expect(!result.contains("alert"), "Payload must not appear in output")
    }

    @Test
    func neutralizesHTML5NamedEntityCasings() {
        // HTML5 standard spellings are &Tab; and &NewLine; (case-sensitive),
        // but our decoder must match any casing to prevent bypasses.
        let tabBypass = "<a href=\"java&Tab;script:alert(1)\">Click</a>"
        let newlineBypass = "<a href=\"java&NewLine;script:alert(1)\">Click</a>"
        #expect(
            HTMLSanitizer.sanitize(tabBypass).contains("about:blank"),
            "&Tab; (HTML5 casing) inside scheme must be neutralized",
        )
        #expect(
            HTMLSanitizer.sanitize(newlineBypass).contains("about:blank"),
            "&NewLine; (HTML5 casing) inside scheme must be neutralized",
        )
    }

    @Test
    func preservesSingleQuotedAttributes() {
        let input = "<a href='https://meet.google.com/abc'>Join</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(result == input, "Single-quoted safe attributes should be preserved")
    }

    @Test
    func stripsMultipleEventHandlers() {
        let input = "<div onclick=\"a()\" onmouseover=\"b()\" onfocus=\"c()\">Content</div>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(!result.contains("onclick"))
        #expect(!result.contains("onmouseover"))
        #expect(!result.contains("onfocus"))
        #expect(result.contains("Content"))
    }

    @Test
    func preservesSafeAttributesAlongsideDangerousOnes() {
        let input = "<a href=\"https://example.com\" onclick=\"steal()\" class=\"link\">Link</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(!result.contains("onclick"))
        #expect(result.contains("href=\"https://example.com\""))
        #expect(result.contains("class=\"link\""))
    }

    // MARK: - Solidus-Separated Attribute Bypass Prevention

    @Test
    func stripsSolidusOnloadBypass() {
        let input = "<svg/onload=alert(1)>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(!result.contains("onload"), "Solidus-separated onload should be stripped")
        #expect(!result.contains("alert"), "Payload should be removed")
    }

    @Test
    func stripsSolidusOnerrorBypass() {
        let input = "<img/onerror=alert(1)>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(!result.contains("onerror"), "Solidus-separated onerror should be stripped")
        #expect(!result.contains("alert"))
    }

    @Test
    func stripsSolidusOnclickBypass() {
        let input = "<div/onclick=alert(1)>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(!result.contains("onclick"), "Solidus-separated onclick should be stripped")
    }

    @Test
    func stripsSolidusEventHandlerKeepsSafeAttributes() {
        let input = "<img/src=\"x\"/onerror=\"alert(1)\">"
        let result = HTMLSanitizer.sanitize(input)
        #expect(!result.contains("onerror"), "onerror should be stripped")
        #expect(result.contains("src=\"x\""), "Safe src attribute should be preserved")
    }

    @Test
    func preservesSelfClosingSlash() {
        let input = "<br/>"
        #expect(HTMLSanitizer.sanitize(input) == "<br/>", "Self-closing slash should be preserved")
    }

    @Test
    func preservesSelfClosingSlashWithSpace() {
        let input = "<br />"
        #expect(
            HTMLSanitizer.sanitize(input) == "<br />",
            "Self-closing with space should be preserved",
        )
    }

    // MARK: - More Edge Cases

    @Test
    func handlesAngledBracketsInTextContent() {
        let input = "If x < 5 and y > 3, then show <p>result</p>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(result.contains("<p>result</p>"))
        #expect(result.contains("x < 5"))
    }

    @Test
    func handlesVeryLargeInput() {
        // 100KB of safe HTML — should not crash or take excessive time
        let chunk = "<p>Normal paragraph content here.</p>"
        let largeInput = String(repeating: chunk, count: 2500)
        let result = HTMLSanitizer.sanitize(largeInput)
        #expect(result == largeInput, "Large safe input should pass through unchanged")
    }

    @Test
    func nestedScriptInsideDiv() {
        let input = "<div><p>Before</p><script>evil()</script><p>After</p></div>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(!result.contains("script"))
        #expect(!result.contains("evil"))
        #expect(result.contains("<p>Before</p>"))
        #expect(result.contains("<p>After</p>"))
    }

    @Test
    func handlesNestedDangerousElements() {
        let input = "<div><script><script>nested</script></script></div>"
        let result = HTMLSanitizer.sanitize(input)

        #expect(!result.contains("script"))
    }

    // MARK: - Unquoted Attribute URI Neutralization

    @Test
    func neutralizesUnquotedJavascriptURI() {
        let input = "<a href=javascript:alert(1)>Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            !result.contains("javascript:"),
            "Unquoted javascript: URI should be neutralized",
        )
        #expect(result.contains("about:blank"), "Should be replaced with about:blank")
    }

    @Test
    func neutralizesUnquotedDataURI() {
        let input = "<img src=data:text/html,<script>alert(1)</script>>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            result.contains("about:blank"),
            "Unquoted data: URI should be neutralized to about:blank",
        )
        #expect(!result.contains("alert"), "Payload must not leak outside the tag")
        #expect(!result.contains("script"), "Script content must not appear in output")
    }

    @Test
    func preservesUnquotedSafeHref() {
        let input = "<a href=https://example.com>Link</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            result.contains("href=https://example.com"),
            "Safe unquoted href should be preserved",
        )
    }

    // MARK: - Non-ASCII Character Bypass Prevention

    @Test
    func neutralizesNBSPInScheme() {
        // NBSP (U+00A0) inserted via entity — must not bypass javascript: detection
        let input = "<a href=\"java&#xa0;script:alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            result.contains("about:blank"),
            "NBSP inside scheme should be stripped before check",
        )
        #expect(!result.contains("alert"), "Payload must not appear in output")
    }

    @Test
    func neutralizesZeroWidthSpaceInScheme() {
        // Zero-width space (U+200B) inserted via numeric entity
        let input = "<a href=\"java&#x200B;script:alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            result.contains("about:blank"),
            "Zero-width space inside scheme should be stripped before check",
        )
        #expect(!result.contains("alert"), "Payload must not appear in output")
    }

    @Test
    func neutralizesNBSPEntityInScheme() {
        // Direct NBSP character (not entity-encoded) in the source
        let input = "<a href=\"java\u{00A0}script:alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        #expect(
            result.contains("about:blank"),
            "Direct NBSP char inside scheme should be stripped before check",
        )
    }

    // MARK: - Integration Test: Sanitizer -> NSAttributedString Rendering

    @Test
    func sanitizedHTMLProducesNoJavascriptLinksInRendering() throws {
        let maliciousInputs = [
            "<a href=\"javascript:alert(1)\">Click</a>",
            "<a href=\"&#106;avascript:alert(1)\">Click</a>",
            "<a href=\"javascript&colon;alert(1)\">Click</a>",
            "<a href=\"java&#x0A;script:alert(1)\">Click</a>",
            "<a href=\"java&#xa0;script:alert(1)\">Click</a>",
            "<a href=\"data:text/html,<script>alert(1)</script>\">Click</a>",
        ]

        let dangerousSchemes: Set = ["javascript", "data"]

        for input in maliciousInputs {
            let sanitized = HTMLSanitizer.sanitize(input)

            // Replicate the HTMLTextView rendering pipeline
            let styledHTML = """
            <!DOCTYPE html><html><head><meta charset="UTF-8"></head>
            <body>\(sanitized)</body></html>
            """

            guard let data = styledHTML.data(using: .utf8) else {
                Issue.record("Failed to encode HTML to data for input: \(input)")
                continue
            }

            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]

            let attributedString = try NSAttributedString(
                data: data, options: options, documentAttributes: nil,
            )

            // Enumerate all links in the rendered attributed string
            attributedString.enumerateAttribute(
                .link,
                in: NSRange(location: 0, length: attributedString.length),
            ) { value, _, _ in
                guard let url = value as? URL ?? (value as? String).flatMap({ URL(string: $0) })
                else { return }

                if let scheme = url.scheme?.lowercased() {
                    #expect(
                        !dangerousSchemes.contains(scheme),
                        "Rendered HTML contains dangerous \(scheme): link from input: \(input)",
                    )
                }
            }
        }
    }

    // MARK: - Compound Dangerous Elements

    @Test
    func stripsMultipleDangerousElementsPreservesSafe() {
        let input = """
        <p>Agenda:</p>\
        <script>steal()</script>\
        <ul><li>Item 1</li></ul>\
        <iframe src="evil"></iframe>\
        <style>.evil{}</style>
        """
        let expected = """
        <p>Agenda:</p>\
        \
        <ul><li>Item 1</li></ul>\
        \

        """
        let result = HTMLSanitizer.sanitize(input)

        #expect(result == expected)
    }
}
