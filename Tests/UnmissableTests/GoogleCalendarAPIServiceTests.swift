import Foundation
import Testing
@testable import Unmissable

@MainActor
struct GoogleCalendarAPIServiceTests {
    private var apiService: GoogleCalendarAPIService

    init() {
        let oauth2Service = OAuth2Service()
        apiService = GoogleCalendarAPIService(
            oauth2Service: oauth2Service, linkParser: LinkParser(),
        )
    }

    // MARK: - convertToEvent: Valid Events

    @Test
    func convertToEvent_validEventWithAllFields_returnsCorrectEvent() throws {
        let entry = GCalEventEntry(
            id: "event-123",
            summary: "Team Standup",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T10:00:00Z", date: nil, timeZone: "UTC"),
            end: GCalDateTime(dateTime: "2026-03-20T10:30:00Z", date: nil, timeZone: "UTC"),
            organizer: GCalOrganizer(email: "lead@example.com"),
            description: "Daily standup meeting",
            location: "Room 42",
            attendees: [
                GCalAttendee(
                    email: "dev@example.com",
                    displayName: "Dev",
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

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try #require(event)
        #expect(unwrapped.id == "event-123")
        #expect(unwrapped.title == "Team Standup")
        #expect(unwrapped.organizer == "lead@example.com")
        #expect(unwrapped.calendarId == "primary")
        #expect(!unwrapped.isAllDay)
        #expect(event?.description == "Daily standup meeting")
        #expect(event?.location == "Room 42")
    }

    @Test
    func convertToEvent_minimalEvent_onlyRequiredFields() throws {
        let entry = GCalEventEntry(
            id: "min-1",
            summary: "Quick Chat",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T14:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T14:15:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "work")

        let unwrapped = try #require(event)
        #expect(unwrapped.title == "Quick Chat")
        #expect(unwrapped.organizer == nil)
        #expect(unwrapped.description == nil)
        #expect(unwrapped.location == nil)
        #expect(unwrapped.attendees.isEmpty)
    }

    // MARK: - convertToEvent: Filtered Events

    @Test
    func convertToEvent_cancelledEvent_returnsNil() {
        let entry = GCalEventEntry(
            id: "cancelled-1",
            summary: "Cancelled Meeting",
            status: "cancelled",
            start: GCalDateTime(dateTime: "2026-03-20T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        #expect(apiService.convertToEvent(from: entry, calendarId: "primary") == nil)
    }

    @Test
    func convertToEvent_selfDeclined_returnsNil() {
        let entry = GCalEventEntry(
            id: "declined-1",
            summary: "Meeting I Declined",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: [
                GCalAttendee(
                    email: "me@example.com",
                    displayName: "Me",
                    responseStatus: "declined",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: true,
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        #expect(apiService.convertToEvent(from: entry, calendarId: "primary") == nil)
    }

    @Test
    func convertToEvent_missingId_returnsNil() {
        let entry = GCalEventEntry(
            id: nil,
            summary: "No ID",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        #expect(apiService.convertToEvent(from: entry, calendarId: "primary") == nil)
    }

    @Test
    func convertToEvent_missingSummary_returnsNil() {
        let entry = GCalEventEntry(
            id: "no-title-1",
            summary: nil,
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T10:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T11:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        #expect(apiService.convertToEvent(from: entry, calendarId: "primary") == nil)
    }

    // MARK: - convertToEvent: All-Day Events

    @Test
    func convertToEvent_allDayEvent_usesDateField() throws {
        let entry = GCalEventEntry(
            id: "all-day-1",
            summary: "Company Holiday",
            status: "confirmed",
            start: GCalDateTime(dateTime: nil, date: "2026-03-20", timeZone: nil),
            end: GCalDateTime(dateTime: nil, date: "2026-03-21", timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try #require(event)
        #expect(unwrapped.isAllDay)
        #expect(unwrapped.title == "Company Holiday")
    }

    // MARK: - convertToEvent: Conference Data

    @Test
    func convertToEvent_withConferenceData_extractsMeetLink() throws {
        let entry = GCalEventEntry(
            id: "meet-1",
            summary: "Video Call",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T15:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T16:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: GCalConferenceData(
                entryPoints: [
                    GCalEntryPoint(
                        uri: "https://meet.google.com/abc-defg-hij",
                        entryPointType: "video",
                    ),
                ],
            ),
            hangoutLink: nil,
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try #require(event)
        #expect(
            unwrapped.links.first?.absoluteString == "https://meet.google.com/abc-defg-hij",
        )
    }

    // MARK: - convertToEvent: Attachments

    @Test
    func convertToEvent_withAttachments_parsesAttachmentFields() throws {
        let entry = GCalEventEntry(
            id: "attach-1",
            summary: "Design Review",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T13:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T14:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: [
                GCalAttachment(
                    fileUrl: "https://drive.google.com/file/d/abc123",
                    title: "Design Spec",
                    mimeType: "application/pdf",
                    iconLink: "https://drive.google.com/icon.png",
                    fileId: "abc123",
                ),
            ],
            conferenceData: nil,
            hangoutLink: nil,
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try #require(event)
        #expect(unwrapped.attachments.first?.title == "Design Spec")
        #expect(unwrapped.attachments.first?.mimeType == "application/pdf")
    }

    // MARK: - convertToEvent: HangoutLink Fallback

    @Test
    func convertToEvent_withHangoutLinkButNoConferenceData_extractsMeetLink() throws {
        let entry = GCalEventEntry(
            id: "hangout-1",
            summary: "Hangout Meeting",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T15:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T16:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: nil,
            hangoutLink: "https://meet.google.com/hangout-test-room",
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")
        let unwrapped = try #require(event)

        #expect(
            unwrapped.links.first?.host == "meet.google.com",
            "hangoutLink should be extracted as a meeting link",
        )
    }

    @Test
    func convertToEvent_phoneOnlyEntryPoints_noVideoLink() throws {
        let entry = GCalEventEntry(
            id: "phone-only-1",
            summary: "Phone Meeting",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T15:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T16:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: GCalConferenceData(
                entryPoints: [
                    GCalEntryPoint(uri: "tel:+15550100", entryPointType: "phone"),
                ],
            ),
            hangoutLink: nil,
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")
        let unwrapped = try #require(event)

        #expect(unwrapped.title == "Phone Meeting")
        #expect(unwrapped.links.isEmpty, "tel: URIs should be filtered out of meeting links")
    }

    @Test
    func convertToEvent_malformedDateTimeString_returnsNil() {
        let entry = GCalEventEntry(
            id: "malformed-date",
            summary: "Bad Date Meeting",
            status: "confirmed",
            start: GCalDateTime(dateTime: "not-a-date", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "also-not-a-date", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")
        #expect(event == nil, "Malformed date should result in nil event")
    }

    @Test
    func convertToEvent_missingStartDate_returnsNil() {
        let entry = GCalEventEntry(
            id: "no-start",
            summary: "No Start",
            status: "confirmed",
            start: nil,
            end: GCalDateTime(dateTime: "2026-03-20T16:00:00Z", date: nil, timeZone: nil),
            organizer: nil,
            description: nil,
            location: nil,
            attendees: nil,
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")
        #expect(event == nil, "Missing start date should result in nil event")
    }

    // MARK: - convertToEvent: Attendee Conversion

    @Test
    func convertToEvent_attendeesWithAllFields_mapsCorrectly() throws {
        let entry = GCalEventEntry(
            id: "attendee-1",
            summary: "Team Sync",
            status: "confirmed",
            start: GCalDateTime(dateTime: "2026-03-20T09:00:00Z", date: nil, timeZone: nil),
            end: GCalDateTime(dateTime: "2026-03-20T09:30:00Z", date: nil, timeZone: nil),
            organizer: GCalOrganizer(email: "lead@example.com"),
            description: nil,
            location: nil,
            attendees: [
                GCalAttendee(
                    email: "lead@example.com",
                    displayName: "Lead",
                    responseStatus: "accepted",
                    isOptional: false,
                    isOrganizer: true,
                    isSelf: false,
                ),
                GCalAttendee(
                    email: "me@example.com",
                    displayName: "Me",
                    responseStatus: "accepted",
                    isOptional: false,
                    isOrganizer: false,
                    isSelf: true,
                ),
                GCalAttendee(
                    email: "optional@example.com",
                    displayName: "Optional Person",
                    responseStatus: "tentative",
                    isOptional: true,
                    isOrganizer: false,
                    isSelf: false,
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil,
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try #require(event)
        #expect(unwrapped.attendees.count == 3)
        #expect(unwrapped.attendees.first(where: \.isOrganizer)?.email == "lead@example.com")

        let organizer = unwrapped.attendees.first(where: \.isOrganizer)
        #expect(organizer?.email == "lead@example.com")
        #expect(organizer?.name == "Lead")

        let optional = unwrapped.attendees.first(where: \.isOptional)
        #expect(optional?.email == "optional@example.com")
        #expect(optional?.status == .tentative)
    }
}
