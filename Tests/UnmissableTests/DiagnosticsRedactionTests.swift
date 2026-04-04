import Foundation
@testable import Unmissable
import XCTest

final class DiagnosticsRedactionTests: XCTestCase {
    // MARK: - Event ID Redaction

    func testRedactedEventId_shortId_returnsUnchanged() {
        XCTAssertEqual(PrivacyUtils.redactedEventId("abc"), "abc")
    }

    func testRedactedEventId_longId_truncatesToPrefix() {
        let id = "abc123-long-uuid-string-here"
        let result = PrivacyUtils.redactedEventId(id)
        XCTAssertEqual(result, "abc123…")
        XCTAssertFalse(result.contains("long-uuid"))
    }

    // MARK: - Email Redaction

    func testRedactedEmail_validEmail_showsPrefixAndDomain() {
        let result = PrivacyUtils.redactedEmail("john.doe@example.com")
        XCTAssertEqual(result, "jo***@example.com")
    }

    func testRedactedEmail_nil_returnsNone() {
        XCTAssertEqual(PrivacyUtils.redactedEmail(nil), "<none>")
    }

    func testRedactedEmail_empty_returnsNone() {
        XCTAssertEqual(PrivacyUtils.redactedEmail(""), "<none>")
    }

    func testRedactedEmail_noAtSign_returnsStars() {
        XCTAssertEqual(PrivacyUtils.redactedEmail("not-an-email"), "***")
    }

    // MARK: - Path Redaction

    func testRedactedPath_longPath_showsLastTwoComponents() {
        let path = "/Users/name/Library/Application Support/unmissable/db.sqlite"
        let result = PrivacyUtils.redactedPath(path)
        XCTAssertEqual(result, "…/unmissable/db.sqlite")
        XCTAssertFalse(result.contains("name"))
    }

    func testRedactedPath_shortPath_stillRedactsWithPrefix() {
        let path = "unmissable/db.sqlite"
        XCTAssertEqual(PrivacyUtils.redactedPath(path), "…/unmissable/db.sqlite")
    }

    func testRedactedPath_empty_returnsNone() {
        XCTAssertEqual(PrivacyUtils.redactedPath(""), "<none>")
    }

    // MARK: - URL Redaction

    func testRedactedURL_validURL_showsSchemeAndHost() {
        let url = URL(string: "https://meet.google.com/abc-defg?authuser=0")
        let result = PrivacyUtils.redactedURL(url)
        XCTAssertEqual(result, "https://meet.google.com/***")
        XCTAssertFalse(result.contains("abc-defg"))
        XCTAssertFalse(result.contains("authuser"))
    }

    func testRedactedURL_nil_returnsNone() {
        XCTAssertEqual(PrivacyUtils.redactedURL(nil as URL?), "<none>")
    }

    func testRedactedURL_string_valid() {
        let result = PrivacyUtils.redactedURL("https://zoom.us/j/123456789")
        XCTAssertEqual(result, "https://zoom.us/***")
    }

    // MARK: - Error Redaction

    func testRedactedError_shortMessage_returnsUnchanged() {
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Short error",
        ])
        let result = PrivacyUtils.redactedError(error)
        XCTAssertEqual(result, "Short error")
    }

    func testRedactedErrorString_longMessage_truncates() {
        let longMessage = String(repeating: "x", count: 200)
        let result = PrivacyUtils.redactedErrorString(longMessage)
        XCTAssertTrue(result.count < longMessage.count)
        XCTAssertTrue(result.hasSuffix("…[truncated]"))
    }

    // MARK: - Title Redaction

    func testRedactedTitle_shortTitle_returnsUnchanged() {
        XCTAssertEqual(PrivacyUtils.redactedTitle("Team Standup"), "Team Standup")
    }

    func testRedactedTitle_longTitle_truncatesWithCharCount() {
        let title = "Very Long Meeting Title That Exceeds The Maximum Display Length"
        let result = PrivacyUtils.redactedTitle(title)
        XCTAssertEqual(
            result,
            "Very Long Meeting Title That E…[\(title.count) chars]",
        )
    }

    func testRedactedTitle_nil_returnsUntitled() {
        XCTAssertEqual(PrivacyUtils.redactedTitle(nil), "<untitled>")
    }

    func testRedactedTitle_empty_returnsUntitled() {
        XCTAssertEqual(PrivacyUtils.redactedTitle(""), "<untitled>")
    }
}
