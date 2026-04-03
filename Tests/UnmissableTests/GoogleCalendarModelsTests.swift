@testable import Unmissable
import XCTest

final class GoogleCalendarModelsTests: XCTestCase {
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

    func testGCalEventEntry_fullAPIResponse_decodesAllFields() throws {
        let entry = try decoder.decode(GCalEventEntry.self, from: Self.fullEventEntryJSON)

        XCTAssertEqual(entry.id, "abc123xyz")
        XCTAssertEqual(entry.summary, "Weekly Design Sync")
        XCTAssertEqual(entry.status, "confirmed")
        XCTAssertEqual(entry.start?.dateTime, "2026-03-20T14:00:00-07:00")
        XCTAssertEqual(entry.start?.timeZone, "America/Los_Angeles")
        XCTAssertEqual(entry.end?.dateTime, "2026-03-20T15:00:00-07:00")
        XCTAssertEqual(entry.organizer?.email, "design-lead@example.com")
        XCTAssertEqual(entry.description, "Review latest mockups")
        XCTAssertEqual(entry.location, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(entry.hangoutLink, "https://meet.google.com/abc-defg-hij")

        // Attendees
        XCTAssertEqual(entry.attendees?.map(\.email), ["designer@example.com", "pm@example.com"])
        XCTAssertEqual(entry.attendees?.last?.email, "pm@example.com")
        let selfAttendee = try XCTUnwrap(entry.attendees?.first)
        XCTAssertEqual(selfAttendee.email, "designer@example.com")
        XCTAssertEqual(selfAttendee.displayName, "Designer")
        XCTAssertEqual(selfAttendee.responseStatus, "accepted")
        XCTAssertTrue(try XCTUnwrap(selfAttendee.isSelf))
        XCTAssertFalse(try XCTUnwrap(selfAttendee.isOptional))

        // Conference data
        XCTAssertEqual(
            entry.conferenceData?.entryPoints?.map(\.entryPointType),
            ["video", "phone"],
        )
        XCTAssertEqual(entry.conferenceData?.entryPoints?.last?.entryPointType, "phone")
        XCTAssertEqual(
            entry.conferenceData?.entryPoints?.first?.uri,
            "https://meet.google.com/abc-defg-hij",
        )
        XCTAssertEqual(entry.conferenceData?.entryPoints?.first?.entryPointType, "video")

        // Attachments
        XCTAssertEqual(entry.attachments?.map(\.fileId), ["xyz"])
        XCTAssertEqual(entry.attachments?.first?.mimeType, "application/octet-stream")
        XCTAssertEqual(entry.attachments?.first?.title, "Mockups.fig")
        XCTAssertEqual(entry.attachments?.first?.fileId, "xyz")
    }

    func testGCalEventEntry_minimalEvent_decodesWithNils() throws {
        let json = Data("""
        {
            "id": "minimal-1",
            "summary": "Quick Chat"
        }
        """.utf8)

        let entry = try decoder.decode(GCalEventEntry.self, from: json)

        XCTAssertEqual(entry.id, "minimal-1")
        XCTAssertEqual(entry.summary, "Quick Chat")
        XCTAssertNil(entry.status)
        XCTAssertNil(entry.start)
        XCTAssertNil(entry.end)
        XCTAssertNil(entry.organizer)
        XCTAssertNil(entry.description)
        XCTAssertNil(entry.location)
        XCTAssertNil(entry.attendees)
        XCTAssertNil(entry.conferenceData)
        XCTAssertNil(entry.hangoutLink)
        XCTAssertNil(entry.attachments)
    }

    func testGCalEventEntry_allDayEvent_usesDateNotDateTime() throws {
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

        XCTAssertNil(entry.start?.dateTime)
        XCTAssertEqual(entry.start?.date, "2026-12-25")
        XCTAssertNil(entry.end?.dateTime)
        XCTAssertEqual(entry.end?.date, "2026-12-26")
    }

    // MARK: - GCalAttendee CodingKeys

    func testGCalAttendee_codingKeys_mapPythonStyleFields() throws {
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

        XCTAssertTrue(try XCTUnwrap(attendee.isOptional))
        XCTAssertTrue(try XCTUnwrap(attendee.isOrganizer))
        XCTAssertFalse(try XCTUnwrap(attendee.isSelf))
    }

    // MARK: - Forward Compatibility (Unknown Fields)

    func testGCalEventEntry_unknownFieldsAreIgnored() throws {
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
        XCTAssertEqual(entry.id, "compat-1")
        XCTAssertEqual(entry.summary, "Forward Compat Event")
    }

    func testGCalAttendee_unknownFieldsIgnored() throws {
        let json = Data("""
        {
            "email": "forward@example.com",
            "responseStatus": "accepted",
            "futureField": "ignored"
        }
        """.utf8)

        let attendee = try decoder.decode(GCalAttendee.self, from: json)
        XCTAssertEqual(attendee.email, "forward@example.com")
    }

    // MARK: - Null vs Missing Fields

    func testGCalEventEntry_nullSummaryDecodesAsNil() throws {
        let json = Data("""
        {
            "id": "null-summary",
            "summary": null
        }
        """.utf8)

        let entry = try decoder.decode(GCalEventEntry.self, from: json)
        XCTAssertNil(entry.summary)
    }

    func testGCalEventEntry_emptyAttendeesDecodesAsEmptyArray() throws {
        let json = Data("""
        {
            "id": "empty-attendees",
            "summary": "Meeting",
            "attendees": []
        }
        """.utf8)

        let entry = try decoder.decode(GCalEventEntry.self, from: json)
        XCTAssertEqual(entry.attendees, [])
    }

    // MARK: - GCalCalendarListResponse

    func testGCalCalendarListResponse_decodesCalendarList() throws {
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

        XCTAssertEqual(response.items?.map(\.id), ["primary", "team@group.calendar.google.com"])
        XCTAssertEqual(response.items?.first?.summary, "My Calendar")
        XCTAssertTrue(try XCTUnwrap(response.items?.first?.primary))
        XCTAssertEqual(response.items?.first?.colorId, "1")

        let teamCal = response.items?[1]
        XCTAssertEqual(teamCal?.id, "team@group.calendar.google.com")
        XCTAssertFalse(try XCTUnwrap(teamCal?.primary))
        XCTAssertNil(teamCal?.description)
    }

    // MARK: - GCalEventListResponse

    func testGCalEventListResponse_withPagination_decodesNextPageToken() throws {
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

        XCTAssertEqual(response.items?.map(\.id), ["event-1"])
        XCTAssertEqual(response.nextPageToken, "CiAKGjBpNDd2Nmp2Zml2cXRwYjBpOXA")
    }

    func testGCalEventListResponse_emptyItems_decodesAsEmptyArray() throws {
        let json = Data("""
        {
            "items": []
        }
        """.utf8)

        let response = try decoder.decode(GCalEventListResponse.self, from: json)

        XCTAssertEqual(response.items, [])
        XCTAssertNil(response.nextPageToken)
    }
}
