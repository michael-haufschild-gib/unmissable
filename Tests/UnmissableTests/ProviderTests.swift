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

    func testProviderCaseIterable() {
        let allProviders = Provider.allCases
        XCTAssertEqual(allProviders.count, 5)
        XCTAssertTrue(allProviders.contains(.meet))
        XCTAssertTrue(allProviders.contains(.zoom))
        XCTAssertTrue(allProviders.contains(.teams))
        XCTAssertTrue(allProviders.contains(.webex))
        XCTAssertTrue(allProviders.contains(.generic))
    }
}
