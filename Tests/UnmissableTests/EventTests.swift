@testable import Unmissable
import XCTest

final class EventTests: XCTestCase {
    func testEventInitialization() {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(3600) // 1 hour later

        let event = Event(
            id: "test-123",
            title: "Test Meeting",
            startDate: startDate,
            endDate: endDate,
            organizer: "test@example.com",
            calendarId: "primary"
        )

        XCTAssertEqual(event.id, "test-123")
        XCTAssertEqual(event.title, "Test Meeting")
        XCTAssertEqual(event.startDate, startDate)
        XCTAssertEqual(event.endDate, endDate)
        XCTAssertEqual(event.organizer, "test@example.com")
        XCTAssertEqual(event.calendarId, "primary")
        XCTAssertFalse(event.isAllDay)
        XCTAssertFalse(LinkParser().isOnlineMeeting(event))
        XCTAssertEqual(event.duration, 3600)
    }

    func testEventWithMeetingLinks() throws {
        let meetUrl = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        let zoomUrl = try XCTUnwrap(URL(string: "https://zoom.us/j/123456789"))

        let event = Event(
            id: "test-456",
            title: "Online Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            calendarId: "primary",
            links: [meetUrl, zoomUrl],
            provider: .meet
        )

        XCTAssertTrue(LinkParser().isOnlineMeeting(event))
        XCTAssertEqual(LinkParser().primaryLink(for: event), meetUrl)
        XCTAssertEqual(event.provider, .meet)
        XCTAssertEqual(event.links.count, 2)
    }

    func testEventProviderDefaultsToPrimaryMeetingLinkNotFirstLink() throws {
        let docsUrl = try XCTUnwrap(URL(string: "https://example.com/spec"))
        let meetUrl = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        let linkParser = LinkParser()

        // Use withAutoDetectedProvider since Event.init does not auto-detect provider
        let event = Event.withAutoDetectedProvider(
            id: "test-primary-provider",
            title: "Mixed Links Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            calendarId: "primary",
            links: [docsUrl, meetUrl],
            linkParser: linkParser
        )

        XCTAssertEqual(linkParser.primaryLink(for: event), meetUrl)
        XCTAssertEqual(event.provider, .meet)
    }

    func testTeamsLiveLinkIsOnlineMeeting() throws {
        let teamsLiveUrl = try XCTUnwrap(URL(string: "https://teams.live.com/meet/abc-defg-hij"))
        let linkParser = LinkParser()

        // Use withAutoDetectedProvider since Event.init does not auto-detect provider
        let event = Event.withAutoDetectedProvider(
            id: "test-teams-live",
            title: "Teams Live Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            calendarId: "primary",
            links: [teamsLiveUrl],
            linkParser: linkParser
        )

        XCTAssertTrue(linkParser.isOnlineMeeting(event))
        XCTAssertEqual(linkParser.primaryLink(for: event), teamsLiveUrl)
        XCTAssertEqual(event.provider, .teams)
    }

    func testEventTimezoneHandling() throws {
        let utcDate = Date()
        _ = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let event = Event(
            id: "test-timezone",
            title: "PST Meeting",
            startDate: utcDate,
            endDate: utcDate.addingTimeInterval(3600),
            calendarId: "primary",
            timezone: "America/Los_Angeles"
        )

        // Event stores absolute instants regardless of timezone metadata
        XCTAssertEqual(event.startDate, utcDate)
        XCTAssertEqual(event.timezone, "America/Los_Angeles")
    }

    // MARK: - Duration Edge Cases

    func testZeroDurationEvent() {
        let now = Date()
        let event = Event(
            id: "zero-dur",
            title: "Instant Event",
            startDate: now,
            endDate: now,
            calendarId: "primary"
        )
        XCTAssertEqual(event.duration, 0)
    }

    func testNegativeDurationEvent() {
        let now = Date()
        let event = Event(
            id: "neg-dur",
            title: "Backwards Event",
            startDate: now,
            endDate: now.addingTimeInterval(-600), // endDate before startDate
            calendarId: "primary"
        )
        XCTAssertLessThan(event.duration, 0, "Duration should be negative when endDate is before startDate")
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_003_600)
        let meetURL = try XCTUnwrap(URL(string: "https://meet.google.com/test"))

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
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Event.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.startDate, original.startDate)
        XCTAssertEqual(decoded.endDate, original.endDate)
        XCTAssertEqual(decoded.organizer, original.organizer)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.location, original.location)
        XCTAssertEqual(decoded.attendees.count, original.attendees.count)
        XCTAssertEqual(decoded.isAllDay, original.isAllDay)
        XCTAssertEqual(decoded.calendarId, original.calendarId)
        XCTAssertEqual(decoded.timezone, original.timezone)
        XCTAssertEqual(decoded.links, original.links)
        XCTAssertEqual(decoded.provider, original.provider)
        XCTAssertEqual(decoded.snoozeUntil, original.snoozeUntil)
        XCTAssertEqual(decoded.autoJoinEnabled, original.autoJoinEnabled)
    }

    func testCodableRoundTripWithNilOptionals() throws {
        let original = Event(
            id: "codable-nil",
            title: "Minimal Event",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            calendarId: "primary"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Event.self, from: data)

        XCTAssertNil(decoded.organizer)
        XCTAssertNil(decoded.description)
        XCTAssertNil(decoded.location)
        XCTAssertNil(decoded.provider)
        XCTAssertNil(decoded.snoozeUntil)
        XCTAssertTrue(decoded.attendees.isEmpty)
        XCTAssertTrue(decoded.links.isEmpty)
    }

    // MARK: - withAutoDetectedProvider

    func testWithAutoDetectedProvider_noLinks_nilProvider() {
        let event = Event.withAutoDetectedProvider(
            id: "no-links",
            title: "No Links",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "primary",
            links: [],
            linkParser: LinkParser()
        )
        XCTAssertNil(event.provider, "No links should produce nil provider")
    }

    func testWithAutoDetectedProvider_nonMeetingLink_genericProvider() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/meeting"))
        let event = Event.withAutoDetectedProvider(
            id: "generic-link",
            title: "Generic Link",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "primary",
            links: [url],
            linkParser: LinkParser()
        )
        // Non-meeting URLs don't pass isMeetingURL filter, so detectPrimaryLink returns nil
        XCTAssertNil(event.provider)
    }

    // MARK: - withParsedGoogleMeetLinks

    @MainActor
    func testWithParsedGoogleMeetLinks_linksFromDescription() {
        let event = Event.withParsedGoogleMeetLinks(
            id: "desc-link",
            title: "Regular Title",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: "Join us at https://meet.google.com/xyz-uvwx-stu",
            calendarId: "primary",
            linkParser: LinkParser()
        )
        XCTAssertEqual(event.links.count, 1)
        XCTAssertEqual(event.provider, .meet)
    }

    @MainActor
    func testWithParsedGoogleMeetLinks_linksFromLocation() {
        let event = Event.withParsedGoogleMeetLinks(
            id: "loc-link",
            title: "Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            location: "https://meet.google.com/abc-defg-hij",
            calendarId: "primary",
            linkParser: LinkParser()
        )
        XCTAssertEqual(event.links.count, 1)
    }

    @MainActor
    func testWithParsedGoogleMeetLinks_noMeetLinks_emptyLinks() {
        let event = Event.withParsedGoogleMeetLinks(
            id: "no-meet",
            title: "In-Person Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: "Room 42",
            calendarId: "primary",
            linkParser: LinkParser()
        )
        XCTAssertTrue(event.links.isEmpty)
        XCTAssertNil(event.provider)
    }

    @MainActor
    func testWithParsedGoogleMeetLinks_deduplicatesLinksAcrossFields() {
        let event = Event.withParsedGoogleMeetLinks(
            id: "dedup",
            title: "https://meet.google.com/abc-defg-hij",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: "Join at https://meet.google.com/abc-defg-hij",
            location: "https://meet.google.com/abc-defg-hij",
            calendarId: "primary",
            linkParser: LinkParser()
        )
        XCTAssertEqual(event.links.count, 1, "Duplicate links should be deduplicated")
    }

    // MARK: - Equality

    func testEventEquality() {
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
            updatedAt: createdDate
        )

        let event2 = Event(
            id: "same-id",
            title: "Meeting 1",
            startDate: date1,
            endDate: date2,
            calendarId: "primary",
            createdAt: createdDate,
            updatedAt: createdDate
        )

        XCTAssertEqual(event1, event2)

        let event3 = Event(
            id: "different-id",
            title: "Meeting 1",
            startDate: date1,
            endDate: date2,
            calendarId: "primary",
            createdAt: createdDate,
            updatedAt: createdDate
        )

        XCTAssertNotEqual(event1, event3)
    }
}
