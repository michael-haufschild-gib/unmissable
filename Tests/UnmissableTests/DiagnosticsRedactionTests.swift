import Foundation
import Testing
@testable import Unmissable

struct DiagnosticsRedactionTests {
    // MARK: - Event ID Redaction

    @Test
    func redactedEventId_shortId_returnsUnchanged() {
        #expect(PrivacyUtils.redactedEventId("abc") == "abc")
    }

    @Test
    func redactedEventId_longId_truncatesToPrefix() {
        let id = "abc123-long-uuid-string-here"
        let result = PrivacyUtils.redactedEventId(id)
        #expect(result == "abc123…")
        #expect(!result.contains("long-uuid"))
    }

    // MARK: - Email Redaction

    @Test
    func redactedEmail_validEmail_showsPrefixAndDomain() {
        let result = PrivacyUtils.redactedEmail("john.doe@example.com")
        #expect(result == "jo***@example.com")
    }

    @Test
    func redactedEmail_nil_returnsNone() {
        #expect(PrivacyUtils.redactedEmail(nil) == "<none>")
    }

    @Test
    func redactedEmail_empty_returnsNone() {
        #expect(PrivacyUtils.redactedEmail("") == "<none>")
    }

    @Test
    func redactedEmail_noAtSign_returnsStars() {
        #expect(PrivacyUtils.redactedEmail("not-an-email") == "***")
    }

    // MARK: - Path Redaction

    @Test
    func redactedPath_longPath_showsLastTwoComponents() {
        let path = "/Users/name/Library/Application Support/unmissable/db.sqlite"
        let result = PrivacyUtils.redactedPath(path)
        #expect(result == "…/unmissable/db.sqlite")
        #expect(!result.contains("name"))
    }

    @Test
    func redactedPath_shortPath_stillRedactsWithPrefix() {
        let path = "unmissable/db.sqlite"
        #expect(PrivacyUtils.redactedPath(path) == "…/unmissable/db.sqlite")
    }

    @Test
    func redactedPath_empty_returnsNone() {
        #expect(PrivacyUtils.redactedPath("") == "<none>")
    }

    // MARK: - URL Redaction

    @Test
    func redactedURL_validURL_showsSchemeAndHost() {
        let url = URL(string: "https://meet.google.com/abc-defg?authuser=0")
        let result = PrivacyUtils.redactedURL(url)
        #expect(result == "https://meet.google.com/***")
        #expect(!result.contains("abc-defg"))
        #expect(!result.contains("authuser"))
    }

    @Test
    func redactedURL_nil_returnsNone() {
        #expect(PrivacyUtils.redactedURL(nil as URL?) == "<none>")
    }

    @Test
    func redactedURL_string_valid() {
        let result = PrivacyUtils.redactedURL("https://zoom.us/j/123456789")
        #expect(result == "https://zoom.us/***")
    }

    // MARK: - Error Redaction

    @Test
    func redactedError_shortMessage_returnsUnchanged() {
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Short error",
        ])
        let result = PrivacyUtils.redactedError(error)
        #expect(result == "Short error")
    }

    @Test
    func redactedErrorString_longMessage_truncates() {
        let longMessage = String(repeating: "x", count: 200)
        let result = PrivacyUtils.redactedErrorString(longMessage)
        #expect(result.count < longMessage.count)
        #expect(result.hasSuffix("…[truncated]"))
    }

    // MARK: - Title Redaction

    @Test
    func redactedTitle_shortTitle_returnsUnchanged() {
        #expect(PrivacyUtils.redactedTitle("Team Standup") == "Team Standup")
    }

    @Test
    func redactedTitle_longTitle_truncatesWithCharCount() {
        let title = "Very Long Meeting Title That Exceeds The Maximum Display Length"
        let result = PrivacyUtils.redactedTitle(title)
        #expect(
            result == "Very Long Meeting Title That E…[\(title.count) chars]",
        )
    }

    @Test
    func redactedTitle_nil_returnsUntitled() {
        #expect(PrivacyUtils.redactedTitle(nil) == "<untitled>")
    }

    @Test
    func redactedTitle_empty_returnsUntitled() {
        #expect(PrivacyUtils.redactedTitle("") == "<untitled>")
    }
}
