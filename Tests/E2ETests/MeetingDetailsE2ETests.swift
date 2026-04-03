import Foundation
@testable import Unmissable
import XCTest

/// E2E tests for the meeting details popup flow:
/// event in DB → tap from menu bar → popup shows correct data → popup hide.
@MainActor
final class MeetingDetailsE2ETests: XCTestCase {
    private var env: E2ETestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        env = try await E2ETestEnvironment()
    }

    override func tearDown() async throws {
        env.tearDown()
        env = nil
        try await super.tearDown()
    }

    // MARK: - Basic Popup Flow

    func testPopupShowsCorrectEventData() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-popup-1",
            title: "Popup Test Meeting",
            minutesFromNow: 15,
        )
        try await env.seedEvents([event])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)

        XCTAssertTrue(env.meetingDetailsPopupManager.isPopupVisible)
        XCTAssertEqual(env.meetingDetailsPopupManager.lastShownEvent?.id, event.id)
        XCTAssertEqual(env.meetingDetailsPopupManager.lastShownEvent?.title, "Popup Test Meeting")
    }

    func testPopupHideClearsState() async throws {
        let event = E2EEventBuilder.futureEvent(id: "e2e-popup-hide")
        try await env.seedEvents([event])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)
        XCTAssertTrue(env.meetingDetailsPopupManager.isPopupVisible)

        env.meetingDetailsPopupManager.hidePopup()
        XCTAssertFalse(env.meetingDetailsPopupManager.isPopupVisible)
        XCTAssertNil(env.meetingDetailsPopupManager.lastShownEvent)
    }

    // MARK: - Events with Different Data Shapes

    func testPopupWithOnlineMeetingShowsLink() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-popup-meet",
            title: "Google Meet Popup",
            minutesFromNow: 20,
            provider: .meet,
        )
        try await env.seedEvents([meetEvent])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)

        let shownEvent = try XCTUnwrap(env.meetingDetailsPopupManager.lastShownEvent)
        XCTAssertTrue(LinkParser().isOnlineMeeting(shownEvent))
        let link = try XCTUnwrap(LinkParser().primaryLink(for: shownEvent))
        XCTAssertEqual(link.host, "meet.google.com")
        XCTAssertEqual(shownEvent.provider, .meet)
    }

    func testPopupWithEventWithoutLink() async throws {
        let inPersonEvent = E2EEventBuilder.futureEvent(
            id: "e2e-popup-nlink",
            title: "In-Person Popup Meeting",
            minutesFromNow: 25,
        )
        try await env.seedEvents([inPersonEvent])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)

        let shownEvent = try XCTUnwrap(env.meetingDetailsPopupManager.lastShownEvent)
        XCTAssertFalse(LinkParser().isOnlineMeeting(shownEvent))
        XCTAssertNil(LinkParser().primaryLink(for: shownEvent))
    }

    func testPopupWithEventWithAttendees() async throws {
        let event = Event(
            id: "e2e-popup-attendees",
            title: "Team Meeting with Attendees",
            startDate: Date().addingTimeInterval(1200),
            endDate: Date().addingTimeInterval(4800),
            organizer: "boss@company.com",
            attendees: [
                Attendee(
                    name: "Alice",
                    email: "alice@company.com",
                    status: .accepted,
                    isSelf: false,
                ),
                Attendee(
                    name: "Bob",
                    email: "bob@company.com",
                    status: .tentative,
                    isSelf: false,
                ),
                Attendee(
                    email: "me@company.com",
                    status: .accepted,
                    isSelf: true,
                ),
            ],
            calendarId: "e2e-cal",
        )

        try await env.seedEvents([event])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)

        let shownEvent = try XCTUnwrap(env.meetingDetailsPopupManager.lastShownEvent)
        XCTAssertEqual(
            Set(shownEvent.attendees.map(\.email)),
            Set(["alice@company.com", "bob@company.com", "me@company.com"]),
        )
        XCTAssertEqual(shownEvent.organizer, "boss@company.com")
    }

    // MARK: - Popup Does Not Block While Visible

    func testShowingSecondPopupWhileFirstVisibleIsIdempotent() async throws {
        let event1 = E2EEventBuilder.futureEvent(id: "e2e-popup-dup-1", minutesFromNow: 10)
        let event2 = E2EEventBuilder.futureEvent(id: "e2e-popup-dup-2", minutesFromNow: 20)

        try await env.seedEvents([event1, event2])
        let fetched = try await env.fetchUpcomingEvents()

        let dbEvent1 = try XCTUnwrap(fetched.first { $0.id == "e2e-popup-dup-1" })
        let dbEvent2 = try XCTUnwrap(fetched.first { $0.id == "e2e-popup-dup-2" })

        env.meetingDetailsPopupManager.showPopup(for: dbEvent1)
        XCTAssertTrue(env.meetingDetailsPopupManager.isPopupVisible)
        XCTAssertEqual(env.meetingDetailsPopupManager.lastShownEvent?.id, event1.id)

        // Showing second popup while first is visible — TestSafe implementation ignores
        env.meetingDetailsPopupManager.showPopup(for: dbEvent2)
        XCTAssertTrue(env.meetingDetailsPopupManager.isPopupVisible)
        // First event remains shown (test-safe behavior)
        XCTAssertEqual(env.meetingDetailsPopupManager.lastShownEvent?.id, event1.id)
    }

    // MARK: - Popup and Overlay Coexistence

    func testPopupAndOverlayCanCoexist() async throws {
        let event = E2EEventBuilder.futureEvent(id: "e2e-popup-overlay", minutesFromNow: 10)
        try await env.seedAndSchedule([event])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)

        // Show overlay
        env.overlayManager.showOverlayImmediately(for: dbEvent)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        // Show popup simultaneously
        env.meetingDetailsPopupManager.showPopup(for: dbEvent)
        XCTAssertTrue(env.meetingDetailsPopupManager.isPopupVisible)

        // Both should be visible independently
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertTrue(env.meetingDetailsPopupManager.isPopupVisible)

        // Hiding one doesn't affect the other
        env.meetingDetailsPopupManager.hidePopup()
        XCTAssertFalse(env.meetingDetailsPopupManager.isPopupVisible)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        env.overlayManager.hideOverlay()
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
    }
}
