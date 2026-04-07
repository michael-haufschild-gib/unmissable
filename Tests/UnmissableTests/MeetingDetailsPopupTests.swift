import Foundation
import Testing
@testable import Unmissable

@MainActor
struct MeetingDetailsPopupTests {
    private var popupManager: TestSafeMeetingDetailsPopupManager

    init() {
        popupManager = TestSafeMeetingDetailsPopupManager()
    }

    // MARK: - Basic Popup Functionality Tests

    @Test
    func showPopupBasicFunctionality() {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        #expect(pm.isPopupVisible, "Popup should be visible after showing")
    }

    @Test
    func hidePopupFunctionality() {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        #expect(pm.isPopupVisible, "Popup should be visible after showing")

        pm.hidePopup()
        #expect(!pm.isPopupVisible, "Popup should be hidden after hiding")
    }

    @Test
    func preventMultiplePopupsForSameEvent() {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        #expect(pm.isPopupVisible, "First popup should be visible")

        pm.showPopup(for: sampleEvent)
        #expect(pm.isPopupVisible, "Popup should still be visible, not duplicated")
    }

    // MARK: - Memory Management Tests

    @Test
    func popupCleanupAfterHiding() {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        for _ in 0 ..< 10 {
            pm.showPopup(for: sampleEvent)
            #expect(pm.isPopupVisible)

            pm.hidePopup()
            #expect(!pm.isPopupVisible)
        }

        #expect(!pm.isPopupVisible, "Final state should be hidden")
    }

    @Test
    func hidePopupClosesWindowWithoutAccumulation() async throws {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        try await TestUtilities.waitForAsync(timeout: 10.0) { @MainActor @Sendable in
            pm.isPopupVisible
        }

        pm.hidePopup()
        try await TestUtilities.waitForAsync(timeout: 10.0) { @MainActor @Sendable in
            !pm.isPopupVisible
        }

        #expect(!pm.isPopupVisible)
    }

    // MARK: - Deadlock Prevention Tests

    @Test
    func rapidShowHideCycles() {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        for _ in 0 ..< 20 {
            pm.showPopup(for: sampleEvent)
            pm.hidePopup()
        }

        #expect(!pm.isPopupVisible, "Should end in hidden state")
    }

    @Test
    func concurrentPopupOperations() async throws {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        for _ in 0 ..< 5 {
            pm.showPopup(for: sampleEvent)
            try await TestUtilities.waitForAsync(timeout: 10.0) { @MainActor @Sendable in
                pm.isPopupVisible
            }
            pm.hidePopup()
        }

        #expect(!pm.isPopupVisible, "Should end in hidden state after operations")
    }

    // MARK: - Edge Case Tests

    @Test
    func popupWithEmptyEvent() {
        let pm = popupManager
        let emptyEvent = Event(
            id: "empty",
            title: "",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "test",
        )

        pm.showPopup(for: emptyEvent)
        #expect(pm.isPopupVisible, "Popup should show even for empty event")

        pm.hidePopup()
        #expect(!pm.isPopupVisible)
    }

    @Test
    func popupWithVeryLongContent() {
        let pm = popupManager
        let longDescription = String(repeating: "This is a very long description. ", count: 500)
        let manyAttendees = (1 ... 100).map { index in
            Attendee(
                name: "Very Long Attendee Name \(index)",
                email:
                "very.long.email.address.for.testing.purposes.attendee\(index)@verylongdomainname.example.com",
                status: .accepted,
                isSelf: false,
            )
        }

        let longEvent = Event(
            id: "long",
            title: "Very Long Meeting Title That Should Be Truncated Properly",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: longDescription,
            attendees: manyAttendees,
            calendarId: "test",
        )

        pm.showPopup(for: longEvent)
        #expect(pm.isPopupVisible, "Popup should show even with very long content")

        pm.hidePopup()
        #expect(!pm.isPopupVisible)
    }

    // MARK: - Production UI Tests

    @Test
    func popupInProductionMode() async throws {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)

        try await TestUtilities.waitForAsync(timeout: 10.0) { @MainActor @Sendable in
            pm.isPopupVisible
        }

        #expect(pm.isPopupVisible, "Popup should work in production mode")

        pm.hidePopup()

        try await TestUtilities.waitForAsync(timeout: 10.0) { @MainActor @Sendable in
            !pm.isPopupVisible
        }

        #expect(!pm.isPopupVisible, "Popup should be properly dismissed in production mode")
    }

    // MARK: - UI Integration Tests

    @Test
    func popupPreservesEventDataAfterShow() throws {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)

        let shownEvent = try #require(pm.lastShownEvent)
        #expect(shownEvent.id == sampleEvent.id)
        #expect(shownEvent.title == sampleEvent.title)
        #expect(shownEvent.organizer == sampleEvent.organizer)
        #expect(shownEvent.attendees.map(\.email) == sampleEvent.attendees.map(\.email))

        pm.hidePopup()
    }

    @Test
    func hidePopupClearsLastShownEvent() {
        let pm = popupManager
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        #expect(pm.lastShownEvent?.id == sampleEvent.id, "lastShownEvent should match shown event")

        pm.hidePopup()
        #expect(pm.lastShownEvent == nil, "lastShownEvent should be cleared on hide")
    }

    // MARK: - Performance Tests

    @Test
    func popupPerformanceUnderLoad() {
        let pm = popupManager
        let heavyEvent = Event(
            id: "performance",
            title: "Performance Test Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: String(repeating: "Performance test description. ", count: 1000),
            attendees: (1 ... 200).map { index in
                Attendee(
                    name: "Attendee \(index)",
                    email: "attendee\(index)@example.com",
                    status: .accepted,
                    isSelf: false,
                )
            },
            calendarId: "performance",
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        pm.showPopup(for: heavyEvent)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(pm.isPopupVisible, "Popup should handle heavy content")
        #expect(duration < 0.5, "Popup should appear within 500ms even with heavy content")

        pm.hidePopup()
    }

    // MARK: - Helper Methods

    private func createSampleEvent() -> Event {
        Event(
            id: "sample-\(UUID().uuidString)",
            title: "Sample Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            organizer: "organizer@example.com",
            description: "This is a sample meeting for testing purposes.",
            location: "Conference Room A",
            attendees: [
                Attendee(
                    name: "John Doe",
                    email: "john@example.com",
                    status: .accepted,
                    isOrganizer: true,
                    isSelf: false,
                ),
                Attendee(
                    name: "Jane Smith",
                    email: "jane@example.com",
                    status: .tentative,
                    isSelf: false,
                ),
                Attendee(
                    email: "contractor@external.com",
                    status: .needsAction,
                    isOptional: true,
                    isSelf: false,
                ),
            ],
            calendarId: "primary",
            // swiftlint:disable:next force_unwrapping
            links: [URL(string: "https://meet.google.com/abc-defg-hij")!],
        )
    }
}
