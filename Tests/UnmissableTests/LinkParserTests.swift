import Foundation
import Testing
@testable import Unmissable

@MainActor
struct LinkParserTests {
    private var linkParser: LinkParser

    init() {
        linkParser = LinkParser()
    }

    @Test
    func googleMeetLinkExtraction() {
        let text = "Join the meeting at https://meet.google.com/abc-defg-hij"
        let links = linkParser.extractGoogleMeetLinks(from: text)

        #expect(links.first?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test
    func googleMeetIDExtraction() throws {
        let url = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let meetingId = linkParser.extractGoogleMeetID(from: url)

        #expect(meetingId == "abc-defg-hij")
    }

    @Test
    func googleMeetDetection() throws {
        let meetUrl = try #require(URL(string: "https://meet.google.com/test-room"))
        let shortMeetUrl = try #require(URL(string: "https://g.co/meet/test-room"))
        let regularUrl = try #require(URL(string: "https://example.com"))

        #expect(linkParser.isGoogleMeetURL(meetUrl))
        #expect(linkParser.isGoogleMeetURL(shortMeetUrl))
        #expect(!linkParser.isGoogleMeetURL(regularUrl))
    }

    @Test
    func multipleGoogleMeetLinks() {
        let text = """
        Main meeting: https://meet.google.com/abc-defg-hij
        Backup: https://meet.google.com/xyz-uvwx-stu
        Regular link: https://example.com
        """
        let links = linkParser.extractGoogleMeetLinks(from: text)

        let linkStrings = Set(links.map(\.absoluteString))
        #expect(linkStrings == [
            "https://meet.google.com/abc-defg-hij",
            "https://meet.google.com/xyz-uvwx-stu",
        ])
    }

    @Test
    func noGoogleMeetLinks() {
        let text = "This is a regular text with https://example.com and no meeting links"
        let links = linkParser.extractGoogleMeetLinks(from: text)

        #expect(links.isEmpty)
    }

    @Test
    func googleMeetShortLinkExtraction() {
        let text = "Join via short link https://g.co/meet/abc-defg-hij"
        let links = linkParser.extractGoogleMeetLinks(from: text)

        #expect(links.first?.host?.lowercased() == "g.co")
    }

    @Test
    func duplicateGoogleMeetLinks() {
        let text = """
        https://meet.google.com/abc-defg-hij
        Join at https://meet.google.com/abc-defg-hij
        """
        let links = linkParser.extractGoogleMeetLinks(from: text)

        #expect(
            links.map(\.absoluteString) == ["https://meet.google.com/abc-defg-hij"],
        )
    }

    @Test
    func meetingURLValidation_acceptsGoogleMeetShortLinksOnlyOnMeetPath() throws {
        let validShort = try #require(URL(string: "https://g.co/meet/abc-defg-hij"))
        let invalidShort = try #require(URL(string: "https://g.co/maps"))

        #expect(linkParser.isValidMeetingURL(validShort))
        #expect(!linkParser.isValidMeetingURL(invalidShort))
    }

    @Test
    func meetingURLValidation_acceptsTeamsLiveURL() throws {
        let teamsLive = try #require(URL(string: "https://teams.live.com/meet/abc-defg-hij"))
        #expect(linkParser.isValidMeetingURL(teamsLive))
    }

    // MARK: - isMeetingURL Tests

    @Test
    func isMeetingURL_acceptsHTTPSMeetingDomains() throws {
        let meet = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let zoom = try #require(URL(string: "https://zoom.us/j/123456789"))
        let teams = try #require(
            URL(string: "https://teams.microsoft.com/l/meetup-join/abc"),
        )
        let webex = try #require(URL(string: "https://webex.com/meet/user"))

        #expect(linkParser.isMeetingURL(meet))
        #expect(linkParser.isMeetingURL(zoom))
        #expect(linkParser.isMeetingURL(teams))
        #expect(linkParser.isMeetingURL(webex))
    }

    @Test
    func isMeetingURL_acceptsCustomSchemes() throws {
        let zoommtg = try #require(URL(string: "zoommtg://zoom.us/join?confno=123"))
        let msteams = try #require(
            URL(string: "msteams://teams.microsoft.com/meeting"),
        )
        let webex = try #require(URL(string: "webex://example.webex.com/join/123"))

        #expect(linkParser.isMeetingURL(zoommtg))
        #expect(linkParser.isMeetingURL(msteams))
        #expect(linkParser.isMeetingURL(webex))
    }

    @Test
    func isMeetingURL_rejectsNonMeetingURLs() throws {
        let docs = try #require(
            URL(string: "https://docs.google.com/document/d/abc"),
        )
        let generic = try #require(URL(string: "https://example.com/page"))
        let http = try #require(URL(string: "http://meet.google.com/abc"))
        let unknownScheme = try #require(URL(string: "ftp://files.example.com/doc"))

        #expect(!linkParser.isMeetingURL(docs))
        #expect(!linkParser.isMeetingURL(generic))
        #expect(
            !linkParser.isMeetingURL(http),
            "Only HTTPS is accepted for domain-based detection",
        )
        #expect(!linkParser.isMeetingURL(unknownScheme))
    }

    // MARK: - shouldShowJoinButton Tests

    @Test
    func shouldShowJoinButton_moreThan10MinBeforeStart_returnsFalse() throws {
        let meetURL = try #require(URL(string: "https://meet.google.com/abc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(700),
            links: [meetURL],
        )
        #expect(
            !linkParser.shouldShowJoinButton(for: event),
            "Join button should not show more than 10 minutes before start",
        )
    }

    @Test
    func shouldShowJoinButton_within10MinBeforeStart_returnsTrue() throws {
        let url = try #require(URL(string: "https://meet.google.com/abc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(500),
            links: [url],
        )
        #expect(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should show within 10 minutes of start",
        )
    }

    @Test
    func shouldShowJoinButton_duringMeeting_returnsTrue() throws {
        let url = try #require(URL(string: "https://zoom.us/j/123"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(-600),
            endDate: Date().addingTimeInterval(3000),
            links: [url],
        )
        #expect(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should show during an active meeting",
        )
    }

    @Test
    func shouldShowJoinButton_afterMeetingEnds_returnsFalse() throws {
        let url = try #require(URL(string: "https://meet.google.com/abc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-3600),
            links: [url],
        )
        #expect(
            !linkParser.shouldShowJoinButton(for: event),
            "Join button should not show after meeting ends",
        )
    }

    @Test
    func shouldShowJoinButton_noMeetingLink_returnsFalse() {
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(300),
            links: [],
        )
        #expect(
            !linkParser.shouldShowJoinButton(for: event),
            "Join button should not show for events without meeting links",
        )
    }

    @Test
    func shouldShowJoinButton_nonMeetingURL_returnsFalse() throws {
        let url = try #require(URL(string: "https://docs.google.com/doc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(300),
            links: [url],
        )
        #expect(
            !linkParser.shouldShowJoinButton(for: event),
            "Join button should not show for non-meeting URLs",
        )
    }

    @Test
    func shouldShowJoinButton_exactlyAtStartTime_returnsTrue() throws {
        let url = try #require(URL(string: "https://meet.google.com/abc"))
        let event = TestUtilities.createTestEvent(
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            links: [url],
        )
        #expect(
            linkParser.shouldShowJoinButton(for: event),
            "Join button should show exactly at start time",
        )
    }

    // MARK: - extractURLs / extractURL Tests

    @Test
    func extractURLs_findsMultipleURLs() {
        let text = "Check https://example.com and https://google.com for details"
        let urls = linkParser.extractURLs(from: text)
        #expect(urls.first?.host == "example.com")
        #expect(urls.last?.host == "google.com")
    }

    @Test
    func extractURLs_emptyStringReturnsEmpty() {
        #expect(linkParser.extractURLs(from: "").isEmpty)
    }

    @Test
    func extractURLs_noURLsReturnsEmpty() {
        #expect(linkParser.extractURLs(from: "Just plain text").isEmpty)
    }

    @Test
    func extractURL_returnsFirstURL() {
        let text = "Visit https://first.com and https://second.com"
        let url = linkParser.extractURL(from: text)
        #expect(url?.host == "first.com")
    }

    @Test
    func extractURL_noURLReturnsNil() {
        #expect(linkParser.extractURL(from: "No links here") == nil)
    }

    // MARK: - Edge Cases

    @Test
    func extractGoogleMeetID_noHyphenReturnsNil() throws {
        let url = try #require(URL(string: "https://meet.google.com/"))
        #expect(linkParser.extractGoogleMeetID(from: url) == nil)
    }

    @Test
    func isValidMeetingURL_subdomainOfTrustedDomain() throws {
        let url = try #require(URL(string: "https://company.zoom.us/j/123"))
        #expect(
            linkParser.isValidMeetingURL(url),
            "Subdomains of trusted domains should be valid",
        )
    }

    @Test
    func isMeetingURL_httpSchemeRejectedForDomainURLs() throws {
        let url = try #require(URL(string: "http://meet.google.com/abc"))
        #expect(
            !linkParser.isMeetingURL(url),
            "HTTP (non-HTTPS) should be rejected for domain-based detection",
        )
    }

    @Test
    func detectPrimaryLink_prioritizesGoogleMeetOverOthers() throws {
        let zoom = try #require(URL(string: "https://zoom.us/j/123"))
        let meet = try #require(URL(string: "https://meet.google.com/abc"))
        let primary = linkParser.detectPrimaryLink(from: [zoom, meet])
        #expect(primary == meet, "Google Meet should have highest priority")
    }

    @Test
    func detectPrimaryLink_emptyListReturnsNil() {
        #expect(linkParser.detectPrimaryLink(from: []) == nil)
    }

    @Test
    func detectPrimaryLink_allNonMeetingURLsReturnsNil() throws {
        let docs = try #require(URL(string: "https://docs.google.com/doc"))
        let example = try #require(URL(string: "https://example.com/page"))
        #expect(linkParser.detectPrimaryLink(from: [docs, example]) == nil)
    }

    @MainActor
    @Test
    func eventWithParsedGoogleMeetLinks() {
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

        #expect(LinkParser().isOnlineMeeting(event))
        #expect(event.links.first?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(event.provider == Provider.meet)
        #expect(
            LinkParser().primaryLink(for: event)?.absoluteString ==
                "https://meet.google.com/abc-defg-hij",
        )
    }

    // MARK: - Expanded Meeting Service Detection

    @Test
    func newServiceDomains() throws {
        let newDomains = [
            "https://meet.jit.si/MyRoom",
            "https://8x8.vc/company/meeting",
            "https://bluejeans.com/123456",
            "https://chime.aws/123456",
            "https://app.ringcentral.com/join/123",
            "https://join.skype.com/abc123",
            "https://skype.com/meeting/abc",
            "https://discord.gg/invite123",
            "https://discord.com/channels/123/456",
            "https://daily.co/myroom",
            "https://gather.town/app/room",
            "https://livestorm.co/p/webinar",
            "https://vowel.com/meeting/abc",
            "https://pop.com/room/abc",
            "https://tuple.app/session/abc",
            "https://demio.com/ref/abc",
            "https://hopin.com/events/abc",
            "https://streamyard.com/abc",
            "https://tandem.chat/room/abc",
        ]
        for urlString in newDomains {
            let url = try #require(URL(string: urlString))
            #expect(
                linkParser.isMeetingURL(url),
                "Expected \(urlString) to be detected as meeting URL",
            )
        }
    }

    @Test
    func newServiceDomainsRequireHTTPS() throws {
        let httpDomains = [
            "http://meet.jit.si/MyRoom",
            "http://bluejeans.com/123",
            "http://chime.aws/123456",
            "http://8x8.vc/company/meeting",
            "http://discord.gg/invite123",
            "http://gather.town/app/room",
        ]
        for urlString in httpDomains {
            let url = try #require(URL(string: urlString))
            #expect(
                !linkParser.isValidMeetingURL(url),
                "Expected \(urlString) to fail HTTPS validation",
            )
        }
    }

    @Test
    func newURLSchemes() throws {
        let schemes = [
            "callto://+1234567890",
            "skype://user?call",
            "discord://channels/123/456",
            "ringcentral://meeting/123",
        ]
        for urlString in schemes {
            let url = try #require(URL(string: urlString))
            #expect(
                linkParser.isMeetingURL(url),
                "Expected \(urlString) scheme to be detected as meeting URL",
            )
        }
    }
}
