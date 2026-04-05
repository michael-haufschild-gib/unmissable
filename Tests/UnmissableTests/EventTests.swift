import Foundation
import Testing
@testable import Unmissable

struct EventTests {
    @Test
    func eventInitialization() {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(3600) // 1 hour later

        let event = Event(
            id: "test-123",
            title: "Test Meeting",
            startDate: startDate,
            endDate: endDate,
            organizer: "test@example.com",
            calendarId: "primary",
        )

        #expect(event.id == "test-123")
        #expect(event.title == "Test Meeting")
        #expect(event.startDate == startDate)
        #expect(event.endDate == endDate)
        #expect(event.organizer == "test@example.com")
        #expect(event.calendarId == "primary")
        #expect(!event.isAllDay)
        #expect(!LinkParser().isOnlineMeeting(event))
        #expect(event.duration == 3600)
    }

    @Test
    func eventWithMeetingLinks() throws {
        let meetUrl = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let zoomUrl = try #require(URL(string: "https://zoom.us/j/123456789"))

        let event = Event(
            id: "test-456",
            title: "Online Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            calendarId: "primary",
            links: [meetUrl, zoomUrl],
            provider: .meet,
        )

        #expect(LinkParser().isOnlineMeeting(event))
        #expect(LinkParser().primaryLink(for: event) == meetUrl)
        #expect(event.provider == .meet)
        #expect(event.links == [meetUrl, zoomUrl])
    }

    @Test
    func eventProviderDefaultsToPrimaryMeetingLinkNotFirstLink() throws {
        let docsUrl = try #require(URL(string: "https://example.com/spec"))
        let meetUrl = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let linkParser = LinkParser()

        // Use withAutoDetectedProvider since Event.init does not auto-detect provider
        let event = Event.withAutoDetectedProvider(
            id: "test-primary-provider",
            title: "Mixed Links Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            calendarId: "primary",
            links: [docsUrl, meetUrl],
            linkParser: linkParser,
        )

        #expect(linkParser.primaryLink(for: event) == meetUrl)
        #expect(event.provider == .meet)
    }

    @Test
    func teamsLiveLinkIsOnlineMeeting() throws {
        let teamsLiveUrl = try #require(URL(string: "https://teams.live.com/meet/abc-defg-hij"))
        let linkParser = LinkParser()

        // Use withAutoDetectedProvider since Event.init does not auto-detect provider
        let event = Event.withAutoDetectedProvider(
            id: "test-teams-live",
            title: "Teams Live Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            calendarId: "primary",
            links: [teamsLiveUrl],
            linkParser: linkParser,
        )

        #expect(linkParser.isOnlineMeeting(event))
        #expect(linkParser.primaryLink(for: event) == teamsLiveUrl)
        #expect(event.provider == .teams)
    }

    @Test
    func eventTimezoneHandling() throws {
        let utcDate = Date()
        _ = try #require(TimeZone(identifier: "America/Los_Angeles"))

        let event = Event(
            id: "test-timezone",
            title: "PST Meeting",
            startDate: utcDate,
            endDate: utcDate.addingTimeInterval(3600),
            calendarId: "primary",
            timezone: "America/Los_Angeles",
        )

        // Event stores absolute instants regardless of timezone metadata
        #expect(event.startDate == utcDate)
        #expect(event.timezone == "America/Los_Angeles")
    }

    // MARK: - Duration Edge Cases

    @Test
    func zeroDurationEvent() {
        let now = Date()
        let event = Event(
            id: "zero-dur",
            title: "Instant Event",
            startDate: now,
            endDate: now,
            calendarId: "primary",
        )
        #expect(event.duration == 0)
    }

    @Test
    func negativeDurationEvent() {
        let now = Date()
        let event = Event(
            id: "neg-dur",
            title: "Backwards Event",
            startDate: now,
            endDate: now.addingTimeInterval(-600), // endDate before startDate
            calendarId: "primary",
        )
        #expect(event.duration < 0, "Duration should be negative when endDate is before startDate")
    }

    // MARK: - Codable Round-Trip

    @Test
    func codableRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_003_600)
        let meetURL = try #require(URL(string: "https://meet.google.com/test"))

        let original = Event(
            id: "codable-test",
            title: "Codable Meeting",
            startDate: start,
            endDate: end,
            organizer: "test@example.com",
            description: "Test description",
            location: "Room 42",
            attendees: [
                Attendee(name: "Alice", email: "alice@example.com", status: .accepted, isSelf: false),
            ],
            isAllDay: false,
            calendarId: "primary",
            timezone: "America/New_York",
            links: [meetURL],
            provider: .meet,
            snoozeUntil: Date(timeIntervalSince1970: 1_700_001_800),
            autoJoinEnabled: true,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Event.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.startDate == original.startDate)
        #expect(decoded.endDate == original.endDate)
        #expect(decoded.organizer == original.organizer)
        #expect(decoded.description == original.description)
        #expect(decoded.location == original.location)
        #expect(decoded.attendees.map(\.email) == ["alice@example.com"])
        #expect(decoded.isAllDay == original.isAllDay)
        #expect(decoded.calendarId == original.calendarId)
        #expect(decoded.timezone == original.timezone)
        #expect(decoded.links == original.links)
        #expect(decoded.provider == original.provider)
        #expect(decoded.snoozeUntil == original.snoozeUntil)
        #expect(decoded.autoJoinEnabled == original.autoJoinEnabled)
    }

    @Test
    func codableRoundTripWithNilOptionals() throws {
        let original = Event(
            id: "codable-nil",
            title: "Minimal Event",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            calendarId: "primary",
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Event.self, from: data)

        #expect(decoded.organizer == nil)
        #expect(decoded.description == nil)
        #expect(decoded.location == nil)
        #expect(decoded.provider == nil)
        #expect(decoded.snoozeUntil == nil)
        #expect(decoded.attendees.isEmpty, "Attendees should be empty array for minimal event")
        #expect(decoded.links.isEmpty, "Links should be empty array for minimal event")
    }

    // MARK: - withAutoDetectedProvider

    @Test
    func withAutoDetectedProvider_noLinks_nilProvider() {
        let event = Event.withAutoDetectedProvider(
            id: "no-links",
            title: "No Links",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "primary",
            links: [],
            linkParser: LinkParser(),
        )
        #expect(event.provider == nil, "No links should produce nil provider")
    }

    @Test
    func withAutoDetectedProvider_nonMeetingLink_genericProvider() throws {
        let url = try #require(URL(string: "https://example.com/meeting"))
        let event = Event.withAutoDetectedProvider(
            id: "generic-link",
            title: "Generic Link",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "primary",
            links: [url],
            linkParser: LinkParser(),
        )
        // Non-meeting URLs don't pass isMeetingURL filter, so detectPrimaryLink returns nil
        #expect(event.provider == nil)
    }

    // MARK: - withParsedGoogleMeetLinks

    @MainActor
    @Test
    func withParsedGoogleMeetLinks_linksFromDescription() {
        let event = Event.withParsedGoogleMeetLinks(
            id: "desc-link",
            title: "Regular Title",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: "Join us at https://meet.google.com/xyz-uvwx-stu",
            calendarId: "primary",
            linkParser: LinkParser(),
        )
        #expect(event.links.first?.host == "meet.google.com")
        #expect(event.provider == .meet)
    }

    @MainActor
    @Test
    func withParsedGoogleMeetLinks_linksFromLocation() {
        let event = Event.withParsedGoogleMeetLinks(
            id: "loc-link",
            title: "Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            location: "https://meet.google.com/abc-defg-hij",
            calendarId: "primary",
            linkParser: LinkParser(),
        )
        #expect(event.links.first?.host == "meet.google.com")
    }

    @MainActor
    @Test
    func withParsedGoogleMeetLinks_noMeetLinks_emptyLinks() {
        let event = Event.withParsedGoogleMeetLinks(
            id: "no-meet",
            title: "In-Person Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: "Room 42",
            calendarId: "primary",
            linkParser: LinkParser(),
        )
        #expect(event.links.isEmpty, "In-person meeting should have no links")
        #expect(event.provider == nil)
    }

    @MainActor
    @Test
    func withParsedGoogleMeetLinks_deduplicatesLinksAcrossFields() {
        let event = Event.withParsedGoogleMeetLinks(
            id: "dedup",
            title: "https://meet.google.com/abc-defg-hij",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: "Join at https://meet.google.com/abc-defg-hij",
            location: "https://meet.google.com/abc-defg-hij",
            calendarId: "primary",
            linkParser: LinkParser(),
        )
        let dedupedLinks = event.links
        #expect(
            dedupedLinks.map(\.host) == ["meet.google.com"],
            "Duplicate links should be deduplicated to exactly one",
        )
    }

    // MARK: - Equality

    @Test
    func eventEquality() {
        let date1 = Date()
        let date2 = date1.addingTimeInterval(3600)
        let createdDate = Date()

        let event1 = Event(
            id: "same-id",
            title: "Meeting 1",
            startDate: date1,
            endDate: date2,
            calendarId: "primary",
            createdAt: createdDate,
            updatedAt: createdDate,
        )

        let event2 = Event(
            id: "same-id",
            title: "Meeting 1",
            startDate: date1,
            endDate: date2,
            calendarId: "primary",
            createdAt: createdDate,
            updatedAt: createdDate,
        )

        #expect(event1 == event2)

        let event3 = Event(
            id: "different-id",
            title: "Meeting 1",
            startDate: date1,
            endDate: date2,
            calendarId: "primary",
            createdAt: createdDate,
            updatedAt: createdDate,
        )

        #expect(event1 != event3)
    }
}
