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

    func testHandlesNestedDangerousElements() {
        let input = "<div><script><script>nested</script></script></div>"
        let result = HTMLSanitizer.sanitize(input)

        XCTAssertFalse(result.contains("script"))
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
