@testable import Unmissable
import XCTest

final class ProviderTests: XCTestCase {
    func testProviderDetectionFromGoogleMeetURL() throws {
        let meetUrl1 = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        let meetUrl2 = try XCTUnwrap(URL(string: "https://g.co/meet/xyz"))

        XCTAssertEqual(Provider.detect(from: meetUrl1), .meet)
        XCTAssertEqual(Provider.detect(from: meetUrl2), .meet)
    }

    func testProviderDetectionFromZoomURL() throws {
        let zoomUrl1 = try XCTUnwrap(URL(string: "https://zoom.us/j/123456789"))
        let zoomUrl2 = try XCTUnwrap(URL(string: "zoommtg://zoom.us/join?confno=123456789"))

        XCTAssertEqual(Provider.detect(from: zoomUrl1), .zoom)
        XCTAssertEqual(Provider.detect(from: zoomUrl2), .zoom)
    }

    func testProviderDetectionFromTeamsURL() throws {
        let teamsUrl1 = try XCTUnwrap(URL(string: "https://teams.microsoft.com/l/meetup-join/..."))
        let teamsUrl2 = try XCTUnwrap(URL(string: "https://teams.live.com/meet/..."))
        let teamsUrl3 = try XCTUnwrap(URL(string: "msteams://teams.microsoft.com/..."))

        XCTAssertEqual(Provider.detect(from: teamsUrl1), .teams)
        XCTAssertEqual(Provider.detect(from: teamsUrl2), .teams)
        XCTAssertEqual(Provider.detect(from: teamsUrl3), .teams)
    }

    func testProviderDetectionFromWebexURL() throws {
        let webexUrl1 = try XCTUnwrap(URL(string: "https://webex.com/meet/user.name"))
        let webexUrl2 = try XCTUnwrap(URL(string: "webex://webex.com/join/..."))

        XCTAssertEqual(Provider.detect(from: webexUrl1), .webex)
        XCTAssertEqual(Provider.detect(from: webexUrl2), .webex)
    }

    func testProviderDetectionFromGenericURL() throws {
        let genericUrl1 = try XCTUnwrap(URL(string: "https://example.com/meeting"))
        let genericUrl2 = try XCTUnwrap(URL(string: "https://custom-platform.com/room/123"))

        XCTAssertEqual(Provider.detect(from: genericUrl1), .generic)
        XCTAssertEqual(Provider.detect(from: genericUrl2), .generic)
    }

    func testProviderDisplayNames() {
        XCTAssertEqual(Provider.meet.displayName, "Google Meet")
        XCTAssertEqual(Provider.zoom.displayName, "Zoom")
        XCTAssertEqual(Provider.teams.displayName, "Microsoft Teams")
        XCTAssertEqual(Provider.webex.displayName, "Cisco Webex")
        XCTAssertEqual(Provider.generic.displayName, "Other")
    }

    func testProviderIconNames() {
        XCTAssertEqual(Provider.meet.iconName, "video.fill")
        XCTAssertEqual(Provider.zoom.iconName, "video.fill")
        XCTAssertEqual(Provider.teams.iconName, "video.fill")
        XCTAssertEqual(Provider.webex.iconName, "video.fill")
        XCTAssertEqual(Provider.generic.iconName, "link")
    }

    // MARK: - Edge Cases

    func testProviderDetectionFromSubdomainZoom() throws {
        let url = try XCTUnwrap(URL(string: "https://us02web.zoom.us/j/123456789"))
        XCTAssertEqual(Provider.detect(from: url), .zoom, "Subdomain zoom URLs should detect as Zoom")
    }

    func testProviderDetectionFromSubdomainWebex() throws {
        let url = try XCTUnwrap(URL(string: "https://company.webex.com/meet/user"))
        XCTAssertEqual(Provider.detect(from: url), .webex, "Subdomain webex URLs should detect as Webex")
    }

    func testProviderDetection_caseInsensitive() throws {
        let url = try XCTUnwrap(URL(string: "https://MEET.GOOGLE.COM/abc"))
        XCTAssertEqual(Provider.detect(from: url), .meet, "Detection should be case-insensitive")
    }

    func testProviderDetection_fileURL_returnsGeneric() throws {
        let url = try XCTUnwrap(URL(string: "file:///Users/test/document.pdf"))
        XCTAssertEqual(Provider.detect(from: url), .generic)
    }

    func testProviderDetection_urlWithPort_detectsCorrectly() throws {
        let url = try XCTUnwrap(URL(string: "https://meet.google.com:443/abc"))
        XCTAssertEqual(Provider.detect(from: url), .meet)
    }

    // MARK: - Codable

    func testProviderCodableRoundTrip() throws {
        for provider in Provider.allCases {
            let data = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(Provider.self, from: data)
            XCTAssertEqual(decoded, provider)
        }
    }

    func testProviderDecodingFromRawValue() throws {
        let json = Data("\"meet\"".utf8)
        let decoded = try JSONDecoder().decode(Provider.self, from: json)
        XCTAssertEqual(decoded, .meet)
    }

    func testProviderDecodingInvalidRawValueThrows() {
        let json = Data("\"slack\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Provider.self, from: json))
    }

    // MARK: - CaseIterable

    func testProviderCaseIterable() {
        let allProviders = Set(Provider.allCases)
        XCTAssertEqual(allProviders.count, 5)
        XCTAssertEqual(allProviders, [.meet, .zoom, .teams, .webex, .generic])
    }
}
