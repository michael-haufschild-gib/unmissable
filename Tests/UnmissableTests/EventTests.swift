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
        XCTAssertFalse(event.isOnlineMeeting)
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

        XCTAssertTrue(event.isOnlineMeeting)
        XCTAssertEqual(event.primaryLink, meetUrl)
        XCTAssertEqual(event.provider, .meet)
        XCTAssertEqual(event.links.count, 2)
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

        // Dates represent absolute instants; convenience properties should not shift time
        XCTAssertEqual(event.localStartDate, event.startDate)
    }

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
