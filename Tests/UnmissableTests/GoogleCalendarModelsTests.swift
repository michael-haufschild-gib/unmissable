import Foundation
import Testing
@testable import Unmissable

struct GoogleCalendarModelsTests {
    private let decoder = JSONDecoder()

    private static let fullEventEntryJSON = Data("""
    {
        "id": "abc123xyz",
        "summary": "Weekly Design Sync",
        "status": "confirmed",
        "start": {
            "dateTime": "2026-03-20T14:00:00-07:00",
            "timeZone": "America/Los_Angeles"
        },
        "end": {
            "dateTime": "2026-03-20T15:00:00-07:00",
            "timeZone": "America/Los_Angeles"
        },
        "organizer": {
            "email": "design-lead@example.com"
        },
        "description": "Review latest mockups",
        "location": "https://meet.google.com/abc-defg-hij",
        "attendees": [
            {
                "email": "designer@example.com",
                "displayName": "Designer",
                "responseStatus": "accepted",
                "optional": false,
                "organizer": false,
                "self": true
            },
            {
                "email": "pm@example.com",
                "responseStatus": "tentative"
            }
        ],
        "conferenceData": {
            "entryPoints": [
                {
                    "uri": "https://meet.google.com/abc-defg-hij",
                    "entryPointType": "video"
                },
                {
                    "uri": "tel:+1-555-0100",
                    "entryPointType": "phone"
                }
            ]
        },
        "hangoutLink": "https://meet.google.com/abc-defg-hij",
        "attachments": [
            {
                "fileUrl": "https://drive.google.com/file/d/xyz",
                "title": "Mockups.fig",
                "mimeType": "application/octet-stream",
                "iconLink": "https://drive.google.com/icon.png",
                "fileId": "xyz"
            }
        ]
    }
    """.utf8)

    // MARK: - GCalEventEntry Decoding

    @Test
    func gCalEventEntry_fullAPIResponse_decodesAllFields() throws {
        let entry = try decoder.decode(GCalEventEntry.self, from: Self.fullEventEntryJSON)

        #expect(entry.id == "abc123xyz")
        #expect(entry.summary == "Weekly Design Sync")
        #expect(entry.status == "confirmed")
        #expect(entry.start?.dateTime == "2026-03-20T14:00:00-07:00")
        #expect(entry.start?.timeZone == "America/Los_Angeles")
        #expect(entry.end?.dateTime == "2026-03-20T15:00:00-07:00")
        #expect(entry.organizer?.email == "design-lead@example.com")
        #expect(entry.description == "Review latest mockups")
        #expect(entry.location == "https://meet.google.com/abc-defg-hij")
        #expect(entry.hangoutLink == "https://meet.google.com/abc-defg-hij")

        // Attendees
        #expect(entry.attendees?.map(\.email) == ["designer@example.com", "pm@example.com"])
        #expect(entry.attendees?.last?.email == "pm@example.com")
        let selfAttendee = try #require(entry.attendees?.first)
        #expect(selfAttendee.email == "designer@example.com")
        #expect(selfAttendee.displayName == "Designer")
        #expect(selfAttendee.responseStatus == "accepted")
        #expect(try #require(selfAttendee.isSelf))
        #expect(try !#require(selfAttendee.isOptional))

        // Conference data
        #expect(
            entry.conferenceData?.entryPoints?.map(\.entryPointType) == ["video", "phone"],
        )
        #expect(entry.conferenceData?.entryPoints?.last?.entryPointType == "phone")
        #expect(
            entry.conferenceData?.entryPoints?.first?.uri == "https://meet.google.com/abc-defg-hij",
        )
        #expect(entry.conferenceData?.entryPoints?.first?.entryPointType == "video")

        // Attachments
        #expect(entry.attachments?.map(\.fileId) == ["xyz"])
        #expect(entry.attachments?.first?.mimeType == "application/octet-stream")
        #expect(entry.attachments?.first?.title == "Mockups.fig")
        #expect(entry.attachments?.first?.fileId == "xyz")
    }

    @Test
    func gCalEventEntry_minimalEvent_decodesWithNils() throws {
        let json = Data("""
        {
            "id": "minimal-1",
            "summary": "Quick Chat"
        }
        """.utf8)

        let entry = try decoder.decode(GCalEventEntry.self, from: json)

        #expect(entry.id == "minimal-1")
        #expect(entry.summary == "Quick Chat")
        #expect(entry.status == nil)
        #expect(entry.start == nil)
        #expect(entry.end == nil)
        #expect(entry.organizer == nil)
        #expect(entry.description == nil)
        #expect(entry.location == nil)
        #expect(entry.attendees == nil)
        #expect(entry.conferenceData == nil)
        #expect(entry.hangoutLink == nil)
        #expect(entry.attachments == nil)
    }

    @Test
    func gCalEventEntry_allDayEvent_usesDateNotDateTime() throws {
        let json = Data("""
        {
            "id": "allday-1",
            "summary": "Holiday",
            "status": "confirmed",
            "start": { "date": "2026-12-25" },
            "end": { "date": "2026-12-26" }
        }
        """.utf8)

        let entry = try decoder.decode(GCalEventEntry.self, from: json)

        #expect(entry.start?.dateTime == nil)
        #expect(entry.start?.date == "2026-12-25")
        #expect(entry.end?.dateTime == nil)
        #expect(entry.end?.date == "2026-12-26")
    }

    // MARK: - GCalAttendee CodingKeys

    @Test
    func gCalAttendee_codingKeys_mapPythonStyleFields() throws {
        // The API uses "optional", "organizer", "self" as field names.
        // CodingKeys map these to isOptional, isOrganizer, isSelf.
        let json = Data("""
        {
            "email": "test@example.com",
            "displayName": "Test User",
            "responseStatus": "accepted",
            "optional": true,
            "organizer": true,
            "self": false
        }
        """.utf8)

        let attendee = try decoder.decode(GCalAttendee.self, from: json)

        #expect(try #require(attendee.isOptional))
        #expect(try #require(attendee.isOrganizer))
        #expect(try !#require(attendee.isSelf))
    }

    // MARK: - Forward Compatibility (Unknown Fields)

    @Test
    func gCalEventEntry_unknownFieldsAreIgnored() throws {
        let json = Data("""
        {
            "id": "compat-1",
            "summary": "Forward Compat Event",
            "newFieldAddedLater": "should be ignored",
            "start": {
                "dateTime": "2026-03-20T10:00:00Z",
                "extraNestedField": true
            }
        }
        """.utf8)

        let entry = try decoder.decode(GCalEventEntry.self, from: json)
        #expect(entry.id == "compat-1")
        #expect(entry.summary == "Forward Compat Event")
    }

    @Test
    func gCalAttendee_unknownFieldsIgnored() throws {
        let json = Data("""
        {
            "email": "forward@example.com",
            "responseStatus": "accepted",
            "futureField": "ignored"
        }
        """.utf8)

        let attendee = try decoder.decode(GCalAttendee.self, from: json)
        #expect(attendee.email == "forward@example.com")
    }

    // MARK: - Null vs Missing Fields

    @Test
    func gCalEventEntry_nullSummaryDecodesAsNil() throws {
        let json = Data("""
        {
            "id": "null-summary",
            "summary": null
        }
        """.utf8)

        let entry = try decoder.decode(GCalEventEntry.self, from: json)
        #expect(entry.summary == nil)
    }

    @Test
    func gCalEventEntry_emptyAttendeesDecodesAsEmptyArray() throws {
        let json = Data("""
        {
            "id": "empty-attendees",
            "summary": "Meeting",
            "attendees": []
        }
        """.utf8)

        let entry = try decoder.decode(GCalEventEntry.self, from: json)
        #expect(entry.attendees.isEmpty)
    }

    // MARK: - GCalCalendarListResponse

    @Test
    func gCalCalendarListResponse_decodesCalendarList() throws {
        let json = Data("""
        {
            "items": [
                {
                    "id": "primary",
                    "summary": "My Calendar",
                    "description": "Personal calendar",
                    "primary": true,
                    "colorId": "1"
                },
                {
                    "id": "team@group.calendar.google.com",
                    "summary": "Team Events",
                    "primary": false
                }
            ]
        }
        """.utf8)

        let response = try decoder.decode(GCalCalendarListResponse.self, from: json)

        #expect(response.items?.map(\.id) == ["primary", "team@group.calendar.google.com"])
        #expect(response.items?.first?.summary == "My Calendar")
        #expect(try #require(response.items?.first?.primary))
        #expect(response.items?.first?.colorId == "1")

        let teamCal = response.items?[1]
        #expect(teamCal?.id == "team@group.calendar.google.com")
        #expect(try !#require(teamCal?.primary))
        #expect(teamCal?.description == nil)
    }

    // MARK: - GCalEventListResponse

    @Test
    func gCalEventListResponse_withPagination_decodesNextPageToken() throws {
        let json = Data("""
        {
            "items": [
                {
                    "id": "event-1",
                    "summary": "Meeting 1"
                }
            ],
            "nextPageToken": "CiAKGjBpNDd2Nmp2Zml2cXRwYjBpOXA"
        }
        """.utf8)

        let response = try decoder.decode(GCalEventListResponse.self, from: json)

        #expect(response.items?.map(\.id) == ["event-1"])
        #expect(response.nextPageToken == "CiAKGjBpNDd2Nmp2Zml2cXRwYjBpOXA")
    }

    @Test
    func gCalEventListResponse_emptyItems_decodesAsEmptyArray() throws {
        let json = Data("""
        {
            "items": []
        }
        """.utf8)

        let response = try decoder.decode(GCalEventListResponse.self, from: json)

        #expect(response.items.isEmpty)
        #expect(response.nextPageToken == nil)
    }
}
