import Foundation
import Testing
@testable import Unmissable

@MainActor
struct EventFilteringTests {
    @Test
    func cancelledEventFiltering() {
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
            hangoutLink: nil,
        )

        let result = apiService.convertToEvent(from: entry, calendarId: "test-calendar")
        #expect(result == nil, "Cancelled events should be filtered out and return nil")
    }

    @Test
    func declinedEventFiltering() {
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
                    isSelf: true,
                ),
                GCalAttendee(
                    email: "other@example.com",
                    displayName: nil,
                    responseStatus: "accepted",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: false,
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let result = apiService.convertToEvent(from: entry, calendarId: "test-calendar")
        #expect(result == nil, "Events where user declined should be filtered out and return nil")
    }

    @Test
    func acceptedEventNotFiltered() throws {
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
                    isSelf: true,
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let result = try #require(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Events where user accepted should NOT be filtered",
        )

        #expect(result.title == "User Accepted Meeting")
        #expect(result.id == "accepted-event-123")
    }

    @Test
    func tentativeEventNotFiltered() throws {
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
                    isSelf: true,
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let result = try #require(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Events where user responded tentative should NOT be filtered",
        )

        #expect(result.title == "User Tentative Meeting")
    }

    @Test
    func eventWithoutCurrentUserNotFiltered() throws {
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
                    isSelf: false,
                ),
                GCalAttendee(
                    email: "other2@example.com",
                    displayName: nil,
                    responseStatus: "declined",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: false,
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let result = try #require(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Events without current user as attendee should NOT be filtered",
        )

        #expect(result.title == "Other People Meeting")
    }

    @Test
    func eventWithMissingStatusDefaultsToConfirmed() throws {
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
            hangoutLink: nil,
        )

        let result = try #require(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Events without status field should default to confirmed and not be filtered",
        )
        #expect(result.title == "Meeting Without Status")
    }

    @Test
    func attendeeSelfFieldParsing() throws {
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
                    isSelf: true,
                ),
                GCalAttendee(
                    email: "other-user@example.com",
                    displayName: nil,
                    responseStatus: "accepted",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: false,
                ),
                GCalAttendee(
                    email: "no-self-field@example.com",
                    displayName: nil,
                    responseStatus: "tentative",
                    isOptional: nil,
                    isOrganizer: nil,
                    isSelf: nil,
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let event = try #require(
            apiService.convertToEvent(from: entry, calendarId: "test-calendar"),
            "Event with attendees should parse successfully",
        )

        #expect(event.attendees.map(\.email).sorted() == [
            "current-user@example.com", "no-self-field@example.com", "other-user@example.com",
        ])

        let currentUser = try #require(event.attendees.first { $0.email == "current-user@example.com" })
        #expect(currentUser.isSelf)

        let otherUser = try #require(event.attendees.first { $0.email == "other-user@example.com" })
        #expect(!otherUser.isSelf)

        let noSelfField = try #require(event.attendees.first { $0.email == "no-self-field@example.com" })
        #expect(!noSelfField.isSelf)
    }
}
