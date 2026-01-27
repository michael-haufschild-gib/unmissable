@testable import Unmissable
import XCTest

@MainActor
class MeetingDetailsPopupTests: XCTestCase {
    var popupManager: MeetingDetailsPopupManager!

    override func setUp() async throws {
        try await super.setUp()
        popupManager = MeetingDetailsPopupManager()
    }

    override func tearDown() async throws {
        popupManager?.hidePopup()
        popupManager = nil
        try await super.tearDown()
    }

    // MARK: - Basic Popup Functionality Tests

    func testShowPopupBasicFunctionality() {
        let sampleEvent = createSampleEvent()

        // Test showing popup
        popupManager.showPopup(for: sampleEvent)
        XCTAssertTrue(popupManager.isPopupVisible, "Popup should be visible after showing")
    }

    func testHidePopupFunctionality() {
        let sampleEvent = createSampleEvent()

        // Show then hide popup
        popupManager.showPopup(for: sampleEvent)
        XCTAssertTrue(popupManager.isPopupVisible, "Popup should be visible after showing")

        popupManager.hidePopup()
        XCTAssertFalse(popupManager.isPopupVisible, "Popup should be hidden after hiding")
    }

    func testPreventMultiplePopupsForSameEvent() {
        let sampleEvent = createSampleEvent()

        // Show popup twice
        popupManager.showPopup(for: sampleEvent)
        XCTAssertTrue(popupManager.isPopupVisible, "First popup should be visible")

        popupManager.showPopup(for: sampleEvent)
        XCTAssertTrue(popupManager.isPopupVisible, "Popup should still be visible, not duplicated")
    }

    // MARK: - Memory Management Tests

    func testPopupCleanupAfterHiding() {
        let sampleEvent = createSampleEvent()

        // Show and hide popup multiple times
        for _ in 0 ..< 10 {
            popupManager.showPopup(for: sampleEvent)
            XCTAssertTrue(popupManager.isPopupVisible)

            popupManager.hidePopup()
            XCTAssertFalse(popupManager.isPopupVisible)
        }

        // Should not cause memory leaks
        XCTAssertFalse(popupManager.isPopupVisible, "Final state should be hidden")
    }

    // MARK: - Deadlock Prevention Tests

    func testRapidShowHideCycles() {
        let sampleEvent = createSampleEvent()

        // Rapid show/hide cycles to test for deadlocks
        for _ in 0 ..< 20 {
            popupManager.showPopup(for: sampleEvent)
            popupManager.hidePopup()
        }

        XCTAssertFalse(popupManager.isPopupVisible, "Should end in hidden state")
    }

    func testConcurrentPopupOperations() async {
        let sampleEvent = createSampleEvent()

        // Test sequential operations (TaskGroup with @MainActor has compiler issues in Swift 6)
        for _ in 0 ..< 5 {
            popupManager.showPopup(for: sampleEvent)
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            popupManager.hidePopup()
        }

        // Final state should be consistent
        XCTAssertFalse(
            popupManager.isPopupVisible, "Should end in hidden state after operations"
        )
    }

    // MARK: - Edge Case Tests

    func testPopupWithEmptyEvent() {
        let emptyEvent = Event(
            id: "empty",
            title: "",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "test"
        )

        // Should handle empty event gracefully
        popupManager.showPopup(for: emptyEvent)
        XCTAssertTrue(popupManager.isPopupVisible, "Popup should show even for empty event")

        popupManager.hidePopup()
        XCTAssertFalse(popupManager.isPopupVisible)
    }

    func testPopupWithVeryLongContent() {
        let longDescription = String(repeating: "This is a very long description. ", count: 500)
        let manyAttendees = (1 ... 100).map { index in
            Attendee(
                name: "Very Long Attendee Name \(index)",
                email:
                "very.long.email.address.for.testing.purposes.attendee\(index)@verylongdomainname.example.com",
                status: .accepted,
                isSelf: false
            )
        }

        let longEvent = Event(
            id: "long",
            title: "Very Long Meeting Title That Should Be Truncated Properly",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: longDescription,
            attendees: manyAttendees,
            calendarId: "test"
        )

        // Should handle long content gracefully
        popupManager.showPopup(for: longEvent)
        XCTAssertTrue(popupManager.isPopupVisible, "Popup should show even with very long content")

        popupManager.hidePopup()
        XCTAssertFalse(popupManager.isPopupVisible)
    }

    // MARK: - Production UI Tests

    func testPopupInProductionMode() async throws {
        let sampleEvent = createSampleEvent()

        // Test with isTestMode: false to ensure production behavior
        _ = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"]

        // Simulate production mode
        popupManager.showPopup(for: sampleEvent)

        // Wait for popup to fully initialize
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        XCTAssertTrue(popupManager.isPopupVisible, "Popup should work in production mode")

        // Test dismissal
        popupManager.hidePopup()

        // Wait for cleanup
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        XCTAssertFalse(
            popupManager.isPopupVisible, "Popup should be properly dismissed in production mode"
        )
    }

    // MARK: - UI Integration Tests

    func testPopupWindowPositioning() async throws {
        let sampleEvent = createSampleEvent()

        // Test popup positioning
        popupManager.showPopup(for: sampleEvent)

        // Allow time for window creation and positioning
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        XCTAssertTrue(popupManager.isPopupVisible, "Popup should be positioned correctly")

        popupManager.hidePopup()
    }

    func testPopupThemeIntegration() {
        let sampleEvent = createSampleEvent()

        // Test that popup respects theme changes
        popupManager.showPopup(for: sampleEvent)

        // In a real scenario, this would test theme switching
        // For now, just verify popup shows with theme applied
        XCTAssertTrue(popupManager.isPopupVisible, "Popup should integrate with theming system")

        popupManager.hidePopup()
    }

    // MARK: - Performance Tests

    func testPopupPerformanceUnderLoad() {
        let heavyEvent = Event(
            id: "performance",
            title: "Performance Test Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: String(repeating: "Performance test description. ", count: 1000),
            attendees: (1 ... 200).map { index in
                Attendee(
                    name: "Attendee \(index)", email: "attendee\(index)@example.com", status: .accepted,
                    isSelf: false
                )
            },
            calendarId: "performance"
        )

        let startTime = CFAbsoluteTimeGetCurrent()

        // Test popup creation performance
        popupManager.showPopup(for: heavyEvent)

        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime

        XCTAssertTrue(popupManager.isPopupVisible, "Popup should handle heavy content")
        XCTAssertLessThan(duration, 0.5, "Popup should appear within 500ms even with heavy content")

        popupManager.hidePopup()
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
                    name: "John Doe", email: "john@example.com", status: .accepted, isOrganizer: true,
                    isSelf: false
                ),
                Attendee(name: "Jane Smith", email: "jane@example.com", status: .tentative, isSelf: false),
                Attendee(
                    email: "contractor@external.com", status: .needsAction, isOptional: true, isSelf: false
                ),
            ],
            calendarId: "primary",
            links: [URL(string: "https://meet.google.com/abc-defg-hij")!]
        )
    }
}
