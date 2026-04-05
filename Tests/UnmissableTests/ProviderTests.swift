import Foundation
import Testing
@testable import Unmissable

struct ProviderTests {
    @Test
    func providerDetectionFromGoogleMeetURL() throws {
        let meetUrl1 = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let meetUrl2 = try #require(URL(string: "https://g.co/meet/xyz"))

        #expect(Provider.detect(from: meetUrl1) == .meet)
        #expect(Provider.detect(from: meetUrl2) == .meet)
    }

    @Test
    func providerDetectionFromZoomURL() throws {
        let zoomUrl1 = try #require(URL(string: "https://zoom.us/j/123456789"))
        let zoomUrl2 = try #require(URL(string: "zoommtg://zoom.us/join?confno=123456789"))

        #expect(Provider.detect(from: zoomUrl1) == .zoom)
        #expect(Provider.detect(from: zoomUrl2) == .zoom)
    }

    @Test
    func providerDetectionFromTeamsURL() throws {
        let teamsUrl1 = try #require(URL(string: "https://teams.microsoft.com/l/meetup-join/..."))
        let teamsUrl2 = try #require(URL(string: "https://teams.live.com/meet/..."))
        let teamsUrl3 = try #require(URL(string: "msteams://teams.microsoft.com/..."))

        #expect(Provider.detect(from: teamsUrl1) == .teams)
        #expect(Provider.detect(from: teamsUrl2) == .teams)
        #expect(Provider.detect(from: teamsUrl3) == .teams)
    }

    @Test
    func providerDetectionFromWebexURL() throws {
        let webexUrl1 = try #require(URL(string: "https://webex.com/meet/user.name"))
        let webexUrl2 = try #require(URL(string: "webex://webex.com/join/..."))

        #expect(Provider.detect(from: webexUrl1) == .webex)
        #expect(Provider.detect(from: webexUrl2) == .webex)
    }

    @Test
    func providerDetectionFromDiscordURL() throws {
        let discordUrl1 = try #require(URL(string: "https://discord.gg/abc123"))
        let discordUrl2 = try #require(URL(string: "https://discord.com/invite/abc123"))
        let discordUrl3 = try #require(URL(string: "discord://discord.com/channels/123"))

        #expect(Provider.detect(from: discordUrl1) == .discord)
        #expect(Provider.detect(from: discordUrl2) == .discord)
        #expect(Provider.detect(from: discordUrl3) == .discord)
    }

    @Test
    func providerDetectionFromGenericURL() throws {
        let genericUrl1 = try #require(URL(string: "https://example.com/meeting"))
        let genericUrl2 = try #require(URL(string: "https://custom-platform.com/room/123"))

        #expect(Provider.detect(from: genericUrl1) == .generic)
        #expect(Provider.detect(from: genericUrl2) == .generic)
    }

    @Test
    func providerDisplayNames() {
        #expect(Provider.meet.displayName == "Google Meet")
        #expect(Provider.zoom.displayName == "Zoom")
        #expect(Provider.teams.displayName == "Microsoft Teams")
        #expect(Provider.webex.displayName == "Cisco Webex")
        #expect(Provider.generic.displayName == "Other")
    }

    @Test
    func providerIconNames() {
        #expect(Provider.meet.iconName == "video.fill")
        #expect(Provider.zoom.iconName == "video.fill")
        #expect(Provider.teams.iconName == "video.fill")
        #expect(Provider.webex.iconName == "video.fill")
        #expect(Provider.generic.iconName == "link")
    }

    // MARK: - Edge Cases

    @Test
    func providerDetectionFromSubdomainZoom() throws {
        let url = try #require(URL(string: "https://us02web.zoom.us/j/123456789"))
        #expect(Provider.detect(from: url) == .zoom, "Subdomain zoom URLs should detect as Zoom")
    }

    @Test
    func providerDetectionFromSubdomainWebex() throws {
        let url = try #require(URL(string: "https://company.webex.com/meet/user"))
        #expect(Provider.detect(from: url) == .webex, "Subdomain webex URLs should detect as Webex")
    }

    @Test
    func providerDetection_caseInsensitive() throws {
        let url = try #require(URL(string: "https://MEET.GOOGLE.COM/abc"))
        #expect(Provider.detect(from: url) == .meet, "Detection should be case-insensitive")
    }

    @Test
    func providerDetection_fileURL_returnsGeneric() throws {
        let url = try #require(URL(string: "file:///Users/test/document.pdf"))
        #expect(Provider.detect(from: url) == .generic)
    }

    @Test
    func providerDetection_urlWithPort_detectsCorrectly() throws {
        let url = try #require(URL(string: "https://meet.google.com:443/abc"))
        #expect(Provider.detect(from: url) == .meet)
    }

    // MARK: - Codable

    @Test
    func providerCodableRoundTrip() throws {
        for provider in Provider.allCases {
            let data = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(Provider.self, from: data)
            #expect(decoded == provider)
        }
    }

    @Test
    func providerDecodingFromRawValue() throws {
        let json = Data("\"meet\"".utf8)
        let decoded = try JSONDecoder().decode(Provider.self, from: json)
        #expect(decoded == .meet)
    }

    @Test
    func providerDecodingInvalidRawValueThrows() {
        let json = Data("\"slack\"".utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Provider.self, from: json) }
    }

    // MARK: - CaseIterable

    @Test
    func providerCaseIterable() {
        let allProviders = Set(Provider.allCases)
        #expect(allProviders == [.meet, .zoom, .teams, .webex, .discord, .generic])
    }
}
