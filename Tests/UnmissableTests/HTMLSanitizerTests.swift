@testable import Unmissable
import XCTest

final class HTMLSanitizerTests: XCTestCase {
    // MARK: - Dangerous Element Removal

    func testStripsScriptTags() {
        let input = "<p>Hello</p><script>alert('xss')</script><p>World</p>"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertEqual(result, "<p>Hello</p><p>World</p>")
    }

    func testStripsScriptTagsCaseInsensitive() {
        let input = "<SCRIPT>alert('xss')</SCRIPT>"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertEqual(result, "")
    }

    func testStripsIframeTags() {
        let input = "<p>Meeting notes</p><iframe src=\"https://evil.com\"></iframe>"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertEqual(result, "<p>Meeting notes</p>")
    }

    func testStripsStyleTags() {
        let input = "<style>body { background: url('https://tracking.com') }</style><p>Content</p>"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertEqual(result, "<p>Content</p>")
    }

    func testStripsObjectAndEmbedTags() {
        let input = "<object data=\"evil.swf\"></object><embed src=\"evil.swf\"/>"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertEqual(result, "")
    }

    func testStripsFormTags() {
        let input = "<form action=\"https://evil.com\"><input type=\"text\"></form>"
        let result = HTMLSanitizer.sanitize(input)

        // input tag without form is harmless rendered text
        XCTAssertFalse(result.contains("form"))
        XCTAssertFalse(result.contains("evil.com"))
    }

    func testStripsLinkMetaBaseTags() {
        let input =
            "<link rel=\"stylesheet\" href=\"evil.css\"><meta http-equiv=\"refresh\"><base href=\"evil\">"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertEqual(result, "")
    }

    // MARK: - Event Handler Removal

    func testStripsOnclickHandlers() {
        let input = "<a href=\"https://meet.google.com\" onclick=\"steal()\">Join</a>"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertFalse(result.contains("onclick"))
        XCTAssertFalse(result.contains("steal"))
        XCTAssertEqual(result, "<a href=\"https://meet.google.com\">Join</a>")
    }

    func testStripsOnerrorHandlers() {
        let input = "<img src=\"x\" onerror=\"alert(1)\">"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertFalse(result.contains("onerror"))
        XCTAssertFalse(result.contains("alert"))
    }

    func testStripsOnloadHandlers() {
        let input = "<body onload=\"malicious()\">"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertFalse(result.contains("onload"))
        XCTAssertFalse(result.contains("malicious"))
    }

    // MARK: - JavaScript URI Neutralization

    func testNeutralizesJavascriptURIs() {
        let input = "<a href=\"javascript:alert(document.cookie)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertFalse(result.contains("javascript:"))
        XCTAssertEqual(result, "<a href=\"about:blank\">Click</a>")
    }

    func testNeutralizesDataURIs() {
        let input = "<img src=\"data:text/html,<script>alert(1)</script>\">"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertFalse(result.lowercased().contains("data:text"))
    }

    // MARK: - Safe Content Preservation

    func testPreservesSafeFormattingTags() {
        let input = "<p><strong>Bold</strong> and <em>italic</em></p>"
        XCTAssertEqual(HTMLSanitizer.sanitize(input), input)
    }

    func testPreservesLists() {
        let input = "<ul><li>Item 1</li><li>Item 2</li></ul>"
        XCTAssertEqual(HTMLSanitizer.sanitize(input), input)
    }

    func testPreservesHeadings() {
        let input = "<h1>Title</h1><h2>Subtitle</h2>"
        XCTAssertEqual(HTMLSanitizer.sanitize(input), input)
    }

    func testPreservesSafeLinks() {
        let input = "<a href=\"https://meet.google.com/abc-def\">Join Meeting</a>"
        XCTAssertEqual(HTMLSanitizer.sanitize(input), input)
    }

    func testPreservesLineBreaks() {
        let input = "Line 1<br>Line 2<br/>Line 3"
        XCTAssertEqual(HTMLSanitizer.sanitize(input), input)
    }

    // MARK: - Edge Cases

    func testHandlesEmptyString() {
        XCTAssertEqual(HTMLSanitizer.sanitize(""), "")
    }

    func testHandlesPlainText() {
        let input = "Just plain text with no HTML"
        XCTAssertEqual(HTMLSanitizer.sanitize(input), input)
    }

    func testHandlesUnclosedTag() {
        // An unclosed tag (no >) should be treated as literal text
        let input = "<p>Hello <strong"
        let result = HTMLSanitizer.sanitize(input)
        // The tokenizer should handle this without crashing
        XCTAssert(result.contains("Hello"))
    }

    func testHandlesUnclosedDangerousTag() {
        // Script tag that never closes
        let input = "<script>alert('xss')"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("alert"), "Script content should be removed even without closing tag")
    }

    func testStripsDataURIWithBase64() {
        let input = "<img src=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==\">"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.lowercased().contains("data:"))
    }

    func testNeutralizesJavascriptURIWithWhitespace() {
        let input = "<a href=\"  javascript:alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("javascript:"), "Leading whitespace should not bypass javascript: detection")
        XCTAssert(result.contains("about:blank"))
    }

    func testNeutralizesEntityEncodedJavascriptURI() {
        let input = "<a href=\"&#106;avascript:alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssert(result.contains("about:blank"), "Entity-encoded javascript: should be neutralized")
    }

    func testNeutralizesHexEntityEncodedJavascriptURI() {
        let input = "<a href=\"&#x6A;avascript:alert(1)\">Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssert(result.contains("about:blank"), "Hex entity-encoded javascript: should be neutralized")
    }

    func testNeutralizesEntityEncodedDataURI() {
        let input = "<img src=\"&#100;ata:text/html,<script>alert(1)</script>\">"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.lowercased().contains("&#100;ata:"), "Entity-encoded data: should be neutralized")
    }

    func testPreservesSingleQuotedAttributes() {
        let input = "<a href='https://meet.google.com/abc'>Join</a>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertEqual(result, input, "Single-quoted safe attributes should be preserved")
    }

    func testStripsMultipleEventHandlers() {
        let input = "<div onclick=\"a()\" onmouseover=\"b()\" onfocus=\"c()\">Content</div>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("onclick"))
        XCTAssertFalse(result.contains("onmouseover"))
        XCTAssertFalse(result.contains("onfocus"))
        XCTAssert(result.contains("Content"))
    }

    func testPreservesSafeAttributesAlongsideDangerousOnes() {
        let input = "<a href=\"https://example.com\" onclick=\"steal()\" class=\"link\">Link</a>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("onclick"))
        XCTAssert(result.contains("href=\"https://example.com\""))
        XCTAssert(result.contains("class=\"link\""))
    }

    // MARK: - Solidus-Separated Attribute Bypass Prevention

    func testStripsSolidusOnloadBypass() {
        let input = "<svg/onload=alert(1)>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("onload"), "Solidus-separated onload should be stripped")
        XCTAssertFalse(result.contains("alert"), "Payload should be removed")
    }

    func testStripsSolidusOnerrorBypass() {
        let input = "<img/onerror=alert(1)>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("onerror"), "Solidus-separated onerror should be stripped")
        XCTAssertFalse(result.contains("alert"))
    }

    func testStripsSolidusOnclickBypass() {
        let input = "<div/onclick=alert(1)>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("onclick"), "Solidus-separated onclick should be stripped")
    }

    func testStripsSolidusEventHandlerKeepsSafeAttributes() {
        let input = "<img/src=\"x\"/onerror=\"alert(1)\">"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("onerror"), "onerror should be stripped")
        XCTAssert(result.contains("src=\"x\""), "Safe src attribute should be preserved")
    }

    func testPreservesSelfClosingSlash() {
        let input = "<br/>"
        XCTAssertEqual(HTMLSanitizer.sanitize(input), "<br/>", "Self-closing slash should be preserved")
    }

    func testPreservesSelfClosingSlashWithSpace() {
        let input = "<br />"
        XCTAssertEqual(HTMLSanitizer.sanitize(input), "<br />", "Self-closing with space should be preserved")
    }

    // MARK: - More Edge Cases

    func testHandlesAngledBracketsInTextContent() {
        let input = "If x < 5 and y > 3, then show <p>result</p>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssert(result.contains("<p>result</p>"))
        XCTAssert(result.contains("x < 5"))
    }

    func testHandlesVeryLargeInput() {
        // 100KB of safe HTML — should not crash or take excessive time
        let chunk = "<p>Normal paragraph content here.</p>"
        let largeInput = String(repeating: chunk, count: 2500)
        let result = HTMLSanitizer.sanitize(largeInput)
        XCTAssertEqual(result, largeInput, "Large safe input should pass through unchanged")
    }

    func testNestedScriptInsideDiv() {
        let input = "<div><p>Before</p><script>evil()</script><p>After</p></div>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("script"))
        XCTAssertFalse(result.contains("evil"))
        XCTAssert(result.contains("<p>Before</p>"))
        XCTAssert(result.contains("<p>After</p>"))
    }

    func testHandlesNestedDangerousElements() {
        let input = "<div><script><script>nested</script></script></div>"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertFalse(result.contains("script"))
    }

    // MARK: - Unquoted Attribute URI Neutralization

    func testNeutralizesUnquotedJavascriptURI() {
        let input = "<a href=javascript:alert(1)>Click</a>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("javascript:"), "Unquoted javascript: URI should be neutralized")
        XCTAssert(result.contains("about:blank"), "Should be replaced with about:blank")
    }

    func testNeutralizesUnquotedDataURI() {
        let input = "<img src=data:text/html,<script>alert(1)</script>>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssertFalse(result.lowercased().contains("data:text"), "Unquoted data: URI should be neutralized")
    }

    func testPreservesUnquotedSafeHref() {
        let input = "<a href=https://example.com>Link</a>"
        let result = HTMLSanitizer.sanitize(input)
        XCTAssert(result.contains("href=https://example.com"), "Safe unquoted href should be preserved")
    }

    func testStripsMultipleDangerousElementsPreservesSafe() {
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

        XCTAssertEqual(result, expected)
    }
}
