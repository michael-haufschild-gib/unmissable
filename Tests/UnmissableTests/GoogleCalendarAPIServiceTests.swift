@testable import Unmissable
import XCTest

@MainActor
final class GoogleCalendarAPIServiceTests: XCTestCase {
    private var apiService: GoogleCalendarAPIService!

    override func setUp() async throws {
        try await super.setUp()
        let oauth2Service = OAuth2Service()
        apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)
    }

    override func tearDown() async throws {
        apiService = nil
        try await super.tearDown()
    }

    // MARK: - convertToEvent: Valid Events

    func testConvertToEvent_validEventWithAllFields_returnsCorrectEvent() throws {
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
                    email: "dev@example.com", displayName: "Dev",
                    responseStatus: "accepted", isOptional: false,
                    isOrganizer: false, isSelf: false
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try XCTUnwrap(event)
        XCTAssertEqual(unwrapped.id, "event-123")
        XCTAssertEqual(unwrapped.title, "Team Standup")
        XCTAssertEqual(unwrapped.organizer, "lead@example.com")
        XCTAssertEqual(unwrapped.calendarId, "primary")
        XCTAssertFalse(unwrapped.isAllDay)
        XCTAssertEqual(event?.description, "Daily standup meeting")
        XCTAssertEqual(event?.location, "Room 42")
    }

    func testConvertToEvent_minimalEvent_onlyRequiredFields() throws {
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
            hangoutLink: nil
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "work")

        let unwrapped = try XCTUnwrap(event)
        XCTAssertEqual(unwrapped.title, "Quick Chat")
        XCTAssertNil(unwrapped.organizer)
        XCTAssertNil(unwrapped.description)
        XCTAssertNil(unwrapped.location)
        XCTAssertTrue(unwrapped.attendees.isEmpty)
    }

    // MARK: - convertToEvent: Filtered Events

    func testConvertToEvent_cancelledEvent_returnsNil() {
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
            hangoutLink: nil
        )

        XCTAssertNil(apiService.convertToEvent(from: entry, calendarId: "primary"))
    }

    func testConvertToEvent_selfDeclined_returnsNil() {
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
                    email: "me@example.com", displayName: "Me",
                    responseStatus: "declined", isOptional: false,
                    isOrganizer: false, isSelf: true
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        XCTAssertNil(apiService.convertToEvent(from: entry, calendarId: "primary"))
    }

    func testConvertToEvent_missingId_returnsNil() {
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
            hangoutLink: nil
        )

        XCTAssertNil(apiService.convertToEvent(from: entry, calendarId: "primary"))
    }

    func testConvertToEvent_missingSummary_returnsNil() {
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
            hangoutLink: nil
        )

        XCTAssertNil(apiService.convertToEvent(from: entry, calendarId: "primary"))
    }

    // MARK: - convertToEvent: All-Day Events

    func testConvertToEvent_allDayEvent_usesDateField() throws {
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
            hangoutLink: nil
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try XCTUnwrap(event)
        XCTAssertTrue(unwrapped.isAllDay)
        XCTAssertEqual(unwrapped.title, "Company Holiday")
    }

    // MARK: - convertToEvent: Conference Data

    func testConvertToEvent_withConferenceData_extractsMeetLink() throws {
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
                    GCalEntryPoint(uri: "https://meet.google.com/abc-defg-hij", entryPointType: "video"),
                ]
            ),
            hangoutLink: nil
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try XCTUnwrap(event)
        XCTAssertFalse(unwrapped.links.isEmpty)
        XCTAssertEqual(unwrapped.links.first?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    // MARK: - convertToEvent: Attachments

    func testConvertToEvent_withAttachments_parsesAttachmentFields() throws {
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
                    fileId: "abc123"
                ),
            ],
            conferenceData: nil,
            hangoutLink: nil
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try XCTUnwrap(event)
        XCTAssertEqual(unwrapped.attachments.count, 1)
        XCTAssertEqual(unwrapped.attachments.first?.title, "Design Spec")
        XCTAssertEqual(unwrapped.attachments.first?.mimeType, "application/pdf")
    }

    // MARK: - convertToEvent: Attendee Conversion

    func testConvertToEvent_attendeesWithAllFields_mapsCorrectly() throws {
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
                    email: "lead@example.com", displayName: "Lead",
                    responseStatus: "accepted", isOptional: false,
                    isOrganizer: true, isSelf: false
                ),
                GCalAttendee(
                    email: "me@example.com", displayName: "Me",
                    responseStatus: "accepted", isOptional: false,
                    isOrganizer: false, isSelf: true
                ),
                GCalAttendee(
                    email: "optional@example.com", displayName: "Optional Person",
                    responseStatus: "tentative", isOptional: true,
                    isOrganizer: false, isSelf: false
                ),
            ],
            attachments: nil,
            conferenceData: nil,
            hangoutLink: nil
        )

        let event = apiService.convertToEvent(from: entry, calendarId: "primary")

        let unwrapped = try XCTUnwrap(event)
        XCTAssertEqual(unwrapped.attendees.count, 3)

        let organizer = unwrapped.attendees.first(where: \.isOrganizer)
        XCTAssertEqual(organizer?.email, "lead@example.com")
        XCTAssertEqual(organizer?.name, "Lead")

        let optional = unwrapped.attendees.first(where: \.isOptional)
        XCTAssertEqual(optional?.email, "optional@example.com")
        XCTAssertEqual(optional?.status, .tentative)
    }
}
