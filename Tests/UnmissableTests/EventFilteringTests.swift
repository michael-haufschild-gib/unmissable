@testable import Unmissable
import XCTest

@MainActor
class EventFilteringTests: XCTestCase {
    func testCancelledEventFiltering() {
        // Test that cancelled events are filtered out during parsing
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)

        // Create mock API response with a cancelled event
        let cancelledEventData: [String: Any] = [
            "id": "cancelled-event-123",
            "summary": "Cancelled Meeting",
            "status": "cancelled",
            "start": ["dateTime": "2025-08-17T10:00:00Z"],
            "end": ["dateTime": "2025-08-17T11:00:00Z"],
            "attendees": [],
        ]

        // Parse the event - should return nil due to cancelled status
        let result = apiService.parseEvent(from: cancelledEventData, calendarId: "test-calendar")

        XCTAssertNil(result, "Cancelled events should be filtered out and return nil")
    }

    func testDeclinedEventFiltering() {
        // Test that events where user declined are filtered out
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)

        // Create mock API response with user declined event
        let declinedEventData: [String: Any] = [
            "id": "declined-event-123",
            "summary": "User Declined Meeting",
            "status": "confirmed",
            "start": ["dateTime": "2025-08-17T10:00:00Z"],
            "end": ["dateTime": "2025-08-17T11:00:00Z"],
            "attendees": [
                [
                    "email": "user@example.com",
                    "responseStatus": "declined",
                    "self": true,
                ],
                [
                    "email": "other@example.com",
                    "responseStatus": "accepted",
                    "self": false,
                ],
            ],
        ]

        // Parse the event - should return nil due to user declined
        let result = apiService.parseEvent(from: declinedEventData, calendarId: "test-calendar")

        XCTAssertNil(result, "Events where user declined should be filtered out and return nil")
    }

    func testAcceptedEventNotFiltered() {
        // Test that confirmed events where user accepted are NOT filtered
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)

        // Create mock API response with user accepted event
        let acceptedEventData: [String: Any] = [
            "id": "accepted-event-123",
            "summary": "User Accepted Meeting",
            "status": "confirmed",
            "start": ["dateTime": "2025-08-17T10:00:00Z"],
            "end": ["dateTime": "2025-08-17T11:00:00Z"],
            "attendees": [
                [
                    "email": "user@example.com",
                    "responseStatus": "accepted",
                    "self": true,
                ],
            ],
        ]

        // Parse the event - should NOT be filtered
        let result = apiService.parseEvent(from: acceptedEventData, calendarId: "test-calendar")

        XCTAssertNotNil(result, "Events where user accepted should NOT be filtered")
        XCTAssertEqual(result?.title, "User Accepted Meeting")
        XCTAssertEqual(result?.id, "accepted-event-123")
    }

    func testTentativeEventNotFiltered() {
        // Test that events where user responded tentative are NOT filtered
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)

        // Create mock API response with user tentative event
        let tentativeEventData: [String: Any] = [
            "id": "tentative-event-123",
            "summary": "User Tentative Meeting",
            "status": "confirmed",
            "start": ["dateTime": "2025-08-17T10:00:00Z"],
            "end": ["dateTime": "2025-08-17T11:00:00Z"],
            "attendees": [
                [
                    "email": "user@example.com",
                    "responseStatus": "tentative",
                    "self": true,
                ],
            ],
        ]

        // Parse the event - should NOT be filtered
        let result = apiService.parseEvent(from: tentativeEventData, calendarId: "test-calendar")

        XCTAssertNotNil(result, "Events where user responded tentative should NOT be filtered")
        XCTAssertEqual(result?.title, "User Tentative Meeting")
    }

    func testEventWithoutCurrentUserNotFiltered() {
        // Test that events where current user is not an attendee are NOT filtered
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)

        // Create mock API response without current user as attendee
        let eventData: [String: Any] = [
            "id": "other-event-123",
            "summary": "Other People Meeting",
            "status": "confirmed",
            "start": ["dateTime": "2025-08-17T10:00:00Z"],
            "end": ["dateTime": "2025-08-17T11:00:00Z"],
            "attendees": [
                [
                    "email": "other1@example.com",
                    "responseStatus": "accepted",
                    "self": false,
                ],
                [
                    "email": "other2@example.com",
                    "responseStatus": "declined",
                    "self": false,
                ],
            ],
        ]

        // Parse the event - should NOT be filtered (no current user attendee)
        let result = apiService.parseEvent(from: eventData, calendarId: "test-calendar")

        XCTAssertNotNil(result, "Events without current user as attendee should NOT be filtered")
        XCTAssertEqual(result?.title, "Other People Meeting")
    }

    func testEventWithMissingStatusDefaultsToConfirmed() {
        // Test that events without status field default to confirmed (not filtered)
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)

        // Create mock API response without status field
        let eventData: [String: Any] = [
            "id": "no-status-event-123",
            "summary": "Meeting Without Status",
            // Missing status field - should default to confirmed
            "start": ["dateTime": "2025-08-17T10:00:00Z"],
            "end": ["dateTime": "2025-08-17T11:00:00Z"],
            "attendees": [],
        ]

        // Parse the event - should NOT be filtered (defaults to confirmed)
        let result = apiService.parseEvent(from: eventData, calendarId: "test-calendar")

        XCTAssertNotNil(
            result, "Events without status field should default to confirmed and not be filtered"
        )
        XCTAssertEqual(result?.title, "Meeting Without Status")
    }

    func testAttendeeSelfFieldParsing() {
        // Test that the isSelf field is correctly parsed from attendee data
        let oauth2Service = OAuth2Service()
        let apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)

        let attendeesData = [
            [
                "email": "current-user@example.com",
                "responseStatus": "accepted",
                "self": true,
            ],
            [
                "email": "other-user@example.com",
                "responseStatus": "accepted",
                "self": false,
            ],
            [
                "email": "no-self-field@example.com",
                "responseStatus": "tentative",
                // Missing self field - should default to false
            ],
        ]

        let attendees = apiService.parseAttendees(from: attendeesData)

        XCTAssertEqual(attendees.count, 3)

        // First attendee should have isSelf = true
        let currentUser = attendees.first { $0.email == "current-user@example.com" }
        XCTAssertNotNil(currentUser)
        XCTAssertTrue(currentUser?.isSelf == true)

        // Second attendee should have isSelf = false
        let otherUser = attendees.first { $0.email == "other-user@example.com" }
        XCTAssertNotNil(otherUser)
        XCTAssertFalse(otherUser?.isSelf == true)

        // Third attendee should default to isSelf = false
        let noSelfField = attendees.first { $0.email == "no-self-field@example.com" }
        XCTAssertNotNil(noSelfField)
        XCTAssertFalse(noSelfField?.isSelf == true)
    }
}
