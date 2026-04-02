import Foundation
import Testing
@testable import Unmissable

// MARK: - Provider Detection Parameterized Tests

struct ProviderDetectionTests {
    @Test(
        "Detect provider from URL",
        arguments: [
            ("https://meet.google.com/abc-defg-hij", Provider.meet),
            ("https://meet.google.com/abc-defg-hij?authuser=0", Provider.meet),
            ("https://g.co/meet/abc-defg-hij", Provider.meet),
            ("https://zoom.us/j/123456789", Provider.zoom),
            ("https://zoom.us/j/123456789?pwd=abc", Provider.zoom),
            ("https://teams.microsoft.com/l/meetup-join/abc", Provider.teams),
            ("https://teams.live.com/meet/abc-defg-hij", Provider.teams),
            ("https://webex.com/meet/john.doe", Provider.webex),
            ("https://example.com/meeting", Provider.generic),
            ("https://docs.google.com/document/d/123", Provider.generic),
        ] as [(String, Provider)]
    )
    func detectProvider(urlString: String, expected: Provider) throws {
        let url = try #require(URL(string: urlString))
        #expect(Provider.detect(from: url) == expected)
    }

    @Test(
        "Every provider's own URL schemes are detected correctly",
        arguments: Provider.allCases.filter { $0 != .generic }
    )
    func providerSchemesRoundTrip(provider: Provider) {
        for scheme in provider.urlSchemes {
            // Append a path component so the URL is valid
            let urlString = scheme.hasSuffix("/") ? "\(scheme)test" : "\(scheme)/test"
            guard let url = URL(string: urlString) else { continue }
            #expect(
                Provider.detect(from: url) == provider,
                "Scheme \(scheme) should detect as \(provider)"
            )
        }
    }

    @Test("Every provider has a non-empty displayName")
    func displayNamesExist() {
        for provider in Provider.allCases {
            #expect(!provider.displayName.isEmpty)
        }
    }
}

// MARK: - Event Duration Parameterized Tests

struct EventPropertyTests {
    @Test(
        "Duration equals endDate minus startDate",
        arguments: [60.0, 300.0, 1800.0, 3600.0, 7200.0, 86_400.0] as [TimeInterval]
    )
    func durationMatchesInterval(interval: TimeInterval) {
        let start = Date()
        let event = Event(
            id: "dur-\(Int(interval))",
            title: "Test",
            startDate: start,
            endDate: start.addingTimeInterval(interval),
            calendarId: "primary"
        )
        #expect(event.duration == interval)
    }

    @Test(
        "isOnlineMeeting is true only when links contain a meeting provider URL",
        arguments: [
            (["https://meet.google.com/abc"], true),
            (["https://zoom.us/j/123"], true),
            (["https://teams.microsoft.com/l/meet/abc"], true),
            (["https://teams.live.com/meet/abc"], true),
            (["https://example.com"], false),
            ([] as [String], false),
            (["https://docs.google.com/doc/d/1"], false),
        ] as [([String], Bool)]
    )
    func onlineMeetingDetection(urlStrings: [String], expected: Bool) {
        let links = urlStrings.compactMap { URL(string: $0) }
        let event = Event(
            id: "online-test",
            title: "Test",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "primary",
            links: links
        )
        #expect(LinkParser().isOnlineMeeting(event) == expected)
    }

    @Test(
        "primaryLink selects the meeting provider URL over generic URLs",
        arguments: [
            (
                ["https://example.com/spec", "https://meet.google.com/abc"],
                "https://meet.google.com/abc"
            ),
            (
                ["https://zoom.us/j/123", "https://example.com"],
                "https://zoom.us/j/123"
            ),
            (
                ["https://example.com"],
                nil as String?
            ),
        ] as [([String], String?)]
    )
    func primaryLinkSelection(urlStrings: [String], expectedString: String?) {
        let links = urlStrings.compactMap { URL(string: $0) }
        let event = Event(
            id: "primary-link-test",
            title: "Test",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "primary",
            links: links
        )
        let expected = expectedString.flatMap { URL(string: $0) }
        #expect(LinkParser().primaryLink(for: event) == expected)
    }

    @Test(
        "Auto-detected provider matches the first meeting link",
        arguments: [
            ("https://meet.google.com/abc", Provider.meet),
            ("https://zoom.us/j/123", Provider.zoom),
            ("https://teams.live.com/meet/abc", Provider.teams),
            ("https://webex.com/meet/john", Provider.webex),
        ] as [(String, Provider)]
    )
    func autoDetectedProvider(urlString: String, expected: Provider) throws {
        let url = try #require(URL(string: urlString))
        let linkParser = LinkParser()
        let event = Event.withAutoDetectedProvider(
            id: "provider-test",
            title: "Test",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "primary",
            links: [url],
            linkParser: linkParser
        )
        #expect(event.provider == expected)
    }
}
