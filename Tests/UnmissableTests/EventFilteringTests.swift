@testable import Unmissable
import XCTest

@MainActor
final class EventFilteringTests: XCTestCase {
    func testCancelledEventFiltering() {
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())

        let entry = GCalEventEntry(
            id: "cancelled-event-123",
            summary: "Cancelled Meeting",
            status: "cancelled",
            start: GCalDateTime(dateTime: "2025-08-17T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2025-08-17T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: [],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        let result = apiService.convertToEvent(from: entry, calendarId: "test-calendar")
        XCTAssertNil(result, "Cancelled events should be filtered out and return nil")
    }

    func testDeclinedEventFiltering() {
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())

        let entry = GCalEventEntry(
            id: "declined-event-123",
            summary: "User Declined Meeting",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2025-08-17T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2025-08-17T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: [
                GCalAttendee(
                    email: "user@example.com",
                    displayName: nil,
                    responseStatus: "declined",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: true
                ),
                GCalAttendee(
                    email: "other@example.com",
                    displayName: nil,
                    responseStatus: "accepted",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: false
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        let result = apiService.convertToEvent(from: entry, calendarId: "test-calendar")
        XCTAssertNil(result, "Events where user declined should be filtered out and return nil")
    }

    func testAcceptedEventNotFiltered() throws {
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())

        let entry = GCalEventEntry(
            id: "accepted-event-123",
            summary: "User Accepted Meeting",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2025-08-17T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2025-08-17T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: [
                GCalAttendee(
                    email: "user@example.com",
                    displayName: nil,
                    responseStatus: "accepted",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: true
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        let result = try XCTUnwrap(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Events where user accepted should NOT be filtered"
        )

        XCTAssertEqual(result.title, "User Accepted Meeting")
        XCTAssertEqual(result.id, "accepted-event-123")
    }

    func testTentativeEventNotFiltered() throws {
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())

        let entry = GCalEventEntry(
            id: "tentative-event-123",
            summary: "User Tentative Meeting",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2025-08-17T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2025-08-17T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: [
                GCalAttendee(
                    email: "user@example.com",
                    displayName: nil,
                    responseStatus: "tentative",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: true
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        let result = try XCTUnwrap(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Events where user responded tentative should NOT be filtered"
        )

        XCTAssertEqual(result.title, "User Tentative Meeting")
    }

    func testEventWithoutCurrentUserNotFiltered() throws {
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())

        let entry = GCalEventEntry(
            id: "other-event-123",
            summary: "Other People Meeting",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2025-08-17T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2025-08-17T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: [
                GCalAttendee(
                    email: "other1@example.com",
                    displayName: nil,
                    responseStatus: "accepted",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: false
                ),
                GCalAttendee(
                    email: "other2@example.com",
                    displayName: nil,
                    responseStatus: "declined",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: false
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        let result = try XCTUnwrap(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Events without current user as attendee should NOT be filtered"
        )

        XCTAssertEqual(result.title, "Other People Meeting")
    }

    func testEventWithMissingStatusDefaultsToConfirmed() throws {
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())

        let entry = GCalEventEntry(
            id: "no-status-event-123",
            summary: "Meeting Without Status",
            status: nil,
            start: GCalDateTime(dateTime: "2025-08-17T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2025-08-17T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: [],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        let result = try XCTUnwrap(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Events without status field should default to confirmed and not be filtered"
        )
        XCTAssertEqual(result.title, "Meeting Without Status")
    }

    func testAttendeeSelfFieldParsing() throws {
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service, linkParser: LinkParser())

        let entry = GCalEventEntry(
            id: "attendee-test-123",
            summary: "Attendee Test Meeting",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2025-08-17T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2025-08-17T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: [
                GCalAttendee(
                    email: "current-user@example.com",
                    displayName: nil,
                    responseStatus: "accepted",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: true
                ),
                GCalAttendee(
                    email: "other-user@example.com",
                    displayName: nil,
                    responseStatus: "accepted",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: false
                ),
                GCalAttendee(
                    email: "no-self-field@example.com",
                    displayName: nil,
                    responseStatus: "tentative",
                    isOptional: nil,
                    isOrganizer: nil,
                    isSelf: nil
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        let event = try XCTUnwrap(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Event with attendees should parse successfully"
        )

        XCTAssertEqual(event.attendees.count, 3)

        let currentUser = try XCTUnwrap(event.attendees.first { $0.email == "current-user@example.com" })
        XCTAssertTrue(currentUser.isSelf)

        let otherUser = try XCTUnwrap(event.attendees.first { $0.email == "other-user@example.com" })
        XCTAssertFalse(otherUser.isSelf)

        let noSelfField = try XCTUnwrap(event.attendees.first { $0.email == "no-self-field@example.com" })
        XCTAssertFalse(noSelfField.isSelf)
    }
}
