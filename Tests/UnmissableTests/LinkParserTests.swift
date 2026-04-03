@testable import Unmissable
import XCTest

final class LinkParserTests: XCTestCase {
    private var linkParser: LinkParser!

    override func setUp() {
        super.setUp()
        linkParser = LinkParser()
    }

    override func tearDown() {
        linkParser = nil
        super.tearDown()
    }

    func testGoogleMeetLinkExtraction() {
        let text = "Join the meeting at https://meet.google.com/abc-defg-hij"
        let links = linkParser.extractGoogleMeetLinks(from: text)

        XCTAssertEqual(links.first?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testGoogleMeetIDExtraction() throws {
        let url = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        let meetingId = linkParser.extractGoogleMeetID(from: url)

        XCTAssertEqual(meetingId, "abc-defg-hij")
    }

    func testGoogleMeetDetection() throws {
        let meetUrl = try XCTUnwrap(URL(string: "https://meet.google.com/test-room"))
        let shortMeetUrl = try XCTUnwrap(URL(string: "https://g.co/meet/test-room"))
        let regularUrl = try XCTUnwrap(URL(string: "https://example.com"))

        XCTAssertTrue(linkParser.isGoogleMeetURL(meetUrl))
        XCTAssertTrue(linkParser.isGoogleMeetURL(shortMeetUrl))
        XCTAssertFalse(linkParser.isGoogleMeetURL(regularUrl))
    }

    func testMultipleGoogleMeetLinks() {
        let text = """
        Main meeting: https://meet.google.com/abc-defg-hij
        Backup: https://meet.google.com/xyz-uvwx-stu
        Regular link: https://example.com
        """
        let links = linkParser.extractGoogleMeetLinks(from: text)

        let linkStrings = Set(links.map(\.absoluteString))
        XCTAssertEqual(linkStrings, [
            "https://meet.google.com/abc-defg-hij",
            "https://meet.google.com/xyz-uvwx-stu",
        ])
    }

    func testNoGoogleMeetLinks() {
        let text = "This is a regular text with https://example.com and no meeting links"
        let links = linkParser.extractGoogleMeetLinks(from: text)

        XCTAssertEqual(links, [])
    }

    func testGoogleMeetShortLinkExtraction() {
        let text = "Join via short link https://g.co/meet/abc-defg-hij"
        let links = linkParser.extractGoogleMeetLinks(from: text)

        XCTAssertEqual(links.first?.host?.lowercased(), "g.co")
    }

    func testDuplicateGoogleMeetLinks() {
        let text = """
        https://meet.google.com/abc-defg-hij
        Join at https://meet.google.com/abc-defg-hij
        """
        let links = linkParser.extractGoogleMeetLinks(from: text)

        XCTAssertEqual(
            links.map(\.absoluteString),
            ["https://meet.google.com/abc-defg-hij"],
        )
    }

    func testMeetingURLValidation_acceptsGoogleMeetShortLinksOnlyOnMeetPath() throws {
        let validShort = try XCTUnwrap(URL(string: "https://g.co/meet/abc-defg-hij"))
        let invalidShort = try XCTUnwrap(URL(string: "https://g.co/maps"))

        XCTAssertTrue(linkParser.isValidMeetingURL(validShort))
        XCTAssertFalse(linkParser.isValidMeetingURL(invalidShort))
    }

    func testMeetingURLValidation_acceptsTeamsLiveURL() throws {
        let teamsLive = try XCTUnwrap(URL(string: "https://teams.live.com/meet/abc-defg-hij"))
        XCTAssertTrue(linkParser.isValidMeetingURL(teamsLive))
    }

    // MARK: - isMeetingURL Tests

    func testIsMeetingURL_acceptsHTTPSMeetingDomains() throws {
        let meet = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        let zoom = try XCTUnwrap(URL(string: "https://zoom.us/j/123456789"))
        let teams = try XCTUnwrap(
            URL(string: "https://teams.microsoft.com/l/meetup-join/abc"),
        )
        let webex = try XCTUnwrap(URL(string: "https://webex.com/meet/user"))

        XCTAssertTrue(linkParser.isMeetingURL(meet))
        XCTAssertTrue(linkParser.isMeetingURL(zoom))
        XCTAssertTrue(linkParser.isMeetingURL(teams))
        XCTAssertTrue(linkParser.isMeetingURL(webex))
    }

    func testIsMeetingURL_acceptsCustomSchemes() throws {
        let zoommtg = try XCTUnwrap(URL(string: "zoommtg://zoom.us/join?confno=123"))
        let msteams = try XCTUnwrap(
            URL(string: "msteams://teams.microsoft.com/meeting"),
        )
        let webex = try XCTUnwrap(URL(string: "webex://example.webex.com/join/123"))

        XCTAssertTrue(linkParser.isMeetingURL(zoommtg))
        XCTAssertTrue(linkParser.isMeetingURL(msteams))
        XCTAssertTrue(linkParser.isMeetingURL(webex))
    }

    func testIsMeetingURL_rejectsNonMeetingURLs() throws {
        let docs = try XCTUnwrap(
            URL(string: "https://docs.google.com/document/d/abc"),
        )
        let generic = try XCTUnwrap(URL(string: "https://example.com/page"))
        let http = try XCTUnwrap(URL(string: "http://meet.google.com/abc"))
        let unknownScheme = try XCTUnwrap(URL(string: "ftp://files.example.com/doc"))

        XCTAssertFalse(linkParser.isMeetingURL(docs))
        XCTAssertFalse(linkParser.isMeetingURL(generic))
        XCTAssertFalse(
            linkParser.isMeetingURL(http),
            "Only HTTPS is accepted for domain-based detection",
        )
        XCTAssertFalse(linkParser.isMeetingURL(unknownScheme))
    }

    // MARK: - shouldShowJoinButton Tests

    func testShouldShowJoinButton_moreThan10MinBeforeStart_returnsFalse() throws {
        let meetURL = try XCTUnwrap(URL(string: "https://meet.google.com/abc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(700),
            links: [meetURL],
        )
        XCTAssertFalse(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should not show more than 10 minutes before start",
        )
    }

    func testShouldShowJoinButton_within10MinBeforeStart_returnsTrue() throws {
        let url = try XCTUnwrap(URL(string: "https://meet.google.com/abc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(500),
            links: [url],
        )
        XCTAssertTrue(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should show within 10 minutes of start",
        )
    }

    func testShouldShowJoinButton_duringMeeting_returnsTrue() throws {
        let url = try XCTUnwrap(URL(string: "https://zoom.us/j/123"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(-600),
            endDate: Date().addingTimeInterval(3000),
            links: [url],
        )
        XCTAssertTrue(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should show during an active meeting",
        )
    }

    func testShouldShowJoinButton_afterMeetingEnds_returnsFalse() throws {
        let url = try XCTUnwrap(URL(string: "https://meet.google.com/abc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-3600),
            links: [url],
        )
        XCTAssertFalse(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should not show after meeting ends",
        )
    }

    func testShouldShowJoinButton_noMeetingLink_returnsFalse() {
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(300),
            links: [],
        )
        XCTAssertFalse(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should not show for events without meeting links",
        )
    }

    func testShouldShowJoinButton_nonMeetingURL_returnsFalse() throws {
        let url = try XCTUnwrap(URL(string: "https://docs.google.com/doc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(300),
            links: [url],
        )
        XCTAssertFalse(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should not show for non-meeting URLs",
        )
    }

    func testShouldShowJoinButton_exactlyAtStartTime_returnsTrue() throws {
        let url = try XCTUnwrap(URL(string: "https://meet.google.com/abc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            links: [url],
        )
        XCTAssertTrue(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should show exactly at start time",
        )
    }

    // MARK: - extractURLs / extractURL Tests

    func testExtractURLs_findsMultipleURLs() {
        let text = "Check https://example.com and https://google.com for details"
        let urls = linkParser.extractURLs(from: text)
        XCTAssertEqual(urls.first?.host, "example.com")
        XCTAssertEqual(urls.last?.host, "google.com")
    }

    func testExtractURLs_emptyStringReturnsEmpty() {
        XCTAssertEqual(linkParser.extractURLs(from: ""), [])
    }

    func testExtractURLs_noURLsReturnsEmpty() {
        XCTAssertEqual(linkParser.extractURLs(from: "Just plain text"), [])
    }

    func testExtractURL_returnsFirstURL() {
        let text = "Visit https://first.com and https://second.com"
        let url = linkParser.extractURL(from: text)
        XCTAssertEqual(url?.host, "first.com")
    }

    func testExtractURL_noURLReturnsNil() {
        XCTAssertNil(linkParser.extractURL(from: "No links here"))
    }

    // MARK: - Edge Cases

    func testExtractGoogleMeetID_noHyphenReturnsNil() throws {
        let url = try XCTUnwrap(URL(string: "https://meet.google.com/"))
        XCTAssertNil(linkParser.extractGoogleMeetID(from: url))
    }

    func testIsValidMeetingURL_subdomainOfTrustedDomain() throws {
        let url = try XCTUnwrap(URL(string: "https://company.zoom.us/j/123"))
        XCTAssertTrue(
            linkParser.isValidMeetingURL(url),
            "Subdomains of trusted domains should be valid",
        )
    }

    func testIsMeetingURL_httpSchemeRejectedForDomainURLs() throws {
        let url = try XCTUnwrap(URL(string: "http://meet.google.com/abc"))
        XCTAssertFalse(
            linkParser.isMeetingURL(url),
            "HTTP (non-HTTPS) should be rejected for domain-based detection",
        )
    }

    func testDetectPrimaryLink_prioritizesGoogleMeetOverOthers() throws {
        let zoom = try XCTUnwrap(URL(string: "https://zoom.us/j/123"))
        let meet = try XCTUnwrap(URL(string: "https://meet.google.com/abc"))
        let primary = linkParser.detectPrimaryLink(from: [zoom, meet])
        XCTAssertEqual(primary, meet, "Google Meet should have highest priority")
    }

    func testDetectPrimaryLink_emptyListReturnsNil() {
        XCTAssertNil(linkParser.detectPrimaryLink(from: []))
    }

    func testDetectPrimaryLink_allNonMeetingURLsReturnsNil() throws {
        let docs = try XCTUnwrap(URL(string: "https://docs.google.com/doc"))
        let example = try XCTUnwrap(URL(string: "https://example.com/page"))
        XCTAssertNil(linkParser.detectPrimaryLink(from: [docs, example]))
    }

    @MainActor
    func testEventWithParsedGoogleMeetLinks() {
        let event = Event.withParsedGoogleMeetLinks(
            id: "test",
            title: "Team Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: "Join us at https://meet.google.com/abc-defg-hij",
            location: "Google Meet",
            calendarId: "primary",
            linkParser: LinkParser(),
        )

        XCTAssertTrue(LinkParser().isOnlineMeeting(event))
        XCTAssertEqual(event.links.first?.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(event.provider, Provider.meet)
        XCTAssertEqual(
            LinkParser().primaryLink(for: event)?.absoluteString,
            "https://meet.google.com/abc-defg-hij",
        )
    }
}
