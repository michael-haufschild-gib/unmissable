import Foundation
import Testing
@testable import Unmissable

/// E2E tests for the meeting details popup flow:
/// event in DB → tap from menu bar → popup shows correct data → popup hide.
@MainActor
struct MeetingDetailsE2ETests {
    private let env: E2ETestEnvironment

    init() async throws {
        env = try await E2ETestEnvironment()
    }

    // MARK: - Basic Popup Flow

    @Test
    func popupShowsCorrectEventData() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-popup-1",
            title: "Popup Test Meeting",
            minutesFromNow: 15,
        )
        try await env.seedEvents([event])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)

        #expect(env.meetingDetailsPopupManager.isPopupVisible)
        #expect(env.meetingDetailsPopupManager.lastShownEvent?.id == event.id)
        #expect(env.meetingDetailsPopupManager.lastShownEvent?.title == "Popup Test Meeting")
    }

    @Test
    func popupHideClearsState() async throws {
        let event = E2EEventBuilder.futureEvent(id: "e2e-popup-hide")
        try await env.seedEvents([event])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)
        #expect(env.meetingDetailsPopupManager.isPopupVisible)

        env.meetingDetailsPopupManager.hidePopup()
        #expect(!env.meetingDetailsPopupManager.isPopupVisible)
        #expect(env.meetingDetailsPopupManager.lastShownEvent == nil)
    }

    // MARK: - Events with Different Data Shapes

    @Test
    func popupWithOnlineMeetingShowsLink() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-popup-meet",
            title: "Google Meet Popup",
            minutesFromNow: 20,
            provider: .meet,
        )
        try await env.seedEvents([meetEvent])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)

        let shownEvent = try #require(env.meetingDetailsPopupManager.lastShownEvent)
        #expect(LinkParser().isOnlineMeeting(shownEvent))
        let link = try #require(LinkParser().primaryLink(for: shownEvent))
        #expect(link.host == "meet.google.com")
        #expect(shownEvent.provider == .meet)
    }

    @Test
    func popupWithEventWithoutLink() async throws {
        let inPersonEvent = E2EEventBuilder.futureEvent(
            id: "e2e-popup-nlink",
            title: "In-Person Popup Meeting",
            minutesFromNow: 25,
        )
        try await env.seedEvents([inPersonEvent])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)

        let shownEvent = try #require(env.meetingDetailsPopupManager.lastShownEvent)
        #expect(!LinkParser().isOnlineMeeting(shownEvent))
        #expect(LinkParser().primaryLink(for: shownEvent) == nil)
    }

    @Test
    func popupWithEventWithAttendees() async throws {
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
        let dbEvent = try #require(fetched.first)

        env.meetingDetailsPopupManager.showPopup(for: dbEvent)

        let shownEvent = try #require(env.meetingDetailsPopupManager.lastShownEvent)
        #expect(
            Set(shownEvent.attendees.map(\.email)) ==
                Set(["alice@company.com", "bob@company.com", "me@company.com"]),
        )
        #expect(shownEvent.organizer == "boss@company.com")
    }

    // MARK: - Popup Does Not Block While Visible

    @Test
    func showingSecondPopupWhileFirstVisibleIsIdempotent() async throws {
        let event1 = E2EEventBuilder.futureEvent(id: "e2e-popup-dup-1", minutesFromNow: 10)
        let event2 = E2EEventBuilder.futureEvent(id: "e2e-popup-dup-2", minutesFromNow: 20)

        try await env.seedEvents([event1, event2])
        let fetched = try await env.fetchUpcomingEvents()

        let dbEvent1 = try #require(fetched.first { $0.id == "e2e-popup-dup-1" })
        let dbEvent2 = try #require(fetched.first { $0.id == "e2e-popup-dup-2" })

        env.meetingDetailsPopupManager.showPopup(for: dbEvent1)
        #expect(env.meetingDetailsPopupManager.isPopupVisible)
        #expect(env.meetingDetailsPopupManager.lastShownEvent?.id == event1.id)

        // Showing second popup while first is visible — TestSafe implementation ignores
        env.meetingDetailsPopupManager.showPopup(for: dbEvent2)
        #expect(env.meetingDetailsPopupManager.isPopupVisible)
        // First event remains shown (test-safe behavior)
        #expect(env.meetingDetailsPopupManager.lastShownEvent?.id == event1.id)
    }

    // MARK: - Popup and Overlay Coexistence

    @Test
    func popupAndOverlayCanCoexist() async throws {
        let event = E2EEventBuilder.futureEvent(id: "e2e-popup-overlay", minutesFromNow: 10)
        try await env.seedAndSchedule([event])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        // Show overlay
        env.overlayManager.showOverlayImmediately(for: dbEvent)
        #expect(env.overlayManager.isOverlayVisible)

        // Show popup simultaneously
        env.meetingDetailsPopupManager.showPopup(for: dbEvent)
        #expect(env.meetingDetailsPopupManager.isPopupVisible)

        // Both should be visible independently
        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.meetingDetailsPopupManager.isPopupVisible)

        // Hiding one doesn't affect the other
        env.meetingDetailsPopupManager.hidePopup()
        #expect(!env.meetingDetailsPopupManager.isPopupVisible)
        #expect(env.overlayManager.isOverlayVisible)

        env.overlayManager.hideOverlay()
        #expect(!env.overlayManager.isOverlayVisible)
    }
}
