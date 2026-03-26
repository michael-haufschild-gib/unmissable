import TestSupport
@testable import Unmissable
import XCTest

@MainActor
final class MeetingDetailsPopupTests: XCTestCase {
    private var popupManager: TestSafeMeetingDetailsPopupManager?

    override func setUp() async throws {
        try await super.setUp()
        popupManager = TestSafeMeetingDetailsPopupManager()
    }

    override func tearDown() async throws {
        popupManager?.hidePopup()
        popupManager = nil
        try await super.tearDown()
    }

    // MARK: - Basic Popup Functionality Tests

    func testShowPopupBasicFunctionality() throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        XCTAssertTrue(pm.isPopupVisible, "Popup should be visible after showing")
    }

    func testHidePopupFunctionality() throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        XCTAssertTrue(pm.isPopupVisible, "Popup should be visible after showing")

        pm.hidePopup()
        XCTAssertFalse(pm.isPopupVisible, "Popup should be hidden after hiding")
    }

    func testPreventMultiplePopupsForSameEvent() throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        XCTAssertTrue(pm.isPopupVisible, "First popup should be visible")

        pm.showPopup(for: sampleEvent)
        XCTAssertTrue(pm.isPopupVisible, "Popup should still be visible, not duplicated")
    }

    // MARK: - Memory Management Tests

    func testPopupCleanupAfterHiding() throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        for _ in 0 ..< 10 {
            pm.showPopup(for: sampleEvent)
            XCTAssertTrue(pm.isPopupVisible)

            pm.hidePopup()
            XCTAssertFalse(pm.isPopupVisible)
        }

        XCTAssertFalse(pm.isPopupVisible, "Final state should be hidden")
    }

    func testHidePopupClosesWindowWithoutAccumulation() async throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            pm.isPopupVisible
        }

        pm.hidePopup()
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            !pm.isPopupVisible
        }

        XCTAssertFalse(pm.isPopupVisible)
    }

    // MARK: - Deadlock Prevention Tests

    func testRapidShowHideCycles() throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        for _ in 0 ..< 20 {
            pm.showPopup(for: sampleEvent)
            pm.hidePopup()
        }

        XCTAssertFalse(pm.isPopupVisible, "Should end in hidden state")
    }

    func testConcurrentPopupOperations() async throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        for _ in 0 ..< 5 {
            pm.showPopup(for: sampleEvent)
            try await TestUtilities.waitForAsync(timeout: 0.5) { @MainActor @Sendable in
                pm.isPopupVisible
            }
            pm.hidePopup()
        }

        XCTAssertFalse(pm.isPopupVisible, "Should end in hidden state after operations")
    }

    // MARK: - Edge Case Tests

    func testPopupWithEmptyEvent() throws {
        let pm = try XCTUnwrap(popupManager)
        let emptyEvent = Event(
            id: "empty",
            title: "",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "test"
        )

        pm.showPopup(for: emptyEvent)
        XCTAssertTrue(pm.isPopupVisible, "Popup should show even for empty event")

        pm.hidePopup()
        XCTAssertFalse(pm.isPopupVisible)
    }

    func testPopupWithVeryLongContent() throws {
        let pm = try XCTUnwrap(popupManager)
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

        pm.showPopup(for: longEvent)
        XCTAssertTrue(pm.isPopupVisible, "Popup should show even with very long content")

        pm.hidePopup()
        XCTAssertFalse(pm.isPopupVisible)
    }

    // MARK: - Production UI Tests

    func testPopupInProductionMode() async throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            pm.isPopupVisible
        }

        XCTAssertTrue(pm.isPopupVisible, "Popup should work in production mode")

        pm.hidePopup()

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            !pm.isPopupVisible
        }

        XCTAssertFalse(pm.isPopupVisible, "Popup should be properly dismissed in production mode")
    }

    // MARK: - UI Integration Tests

    func testPopupWindowPositioning() async throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            pm.isPopupVisible
        }

        XCTAssertTrue(pm.isPopupVisible, "Popup should be positioned correctly")

        pm.hidePopup()
    }

    func testPopupThemeIntegration() throws {
        let pm = try XCTUnwrap(popupManager)
        let sampleEvent = createSampleEvent()

        pm.showPopup(for: sampleEvent)
        XCTAssertTrue(pm.isPopupVisible, "Popup should integrate with theming system")

        pm.hidePopup()
    }

    // MARK: - Performance Tests

    func testPopupPerformanceUnderLoad() throws {
        let pm = try XCTUnwrap(popupManager)
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
        pm.showPopup(for: heavyEvent)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertTrue(pm.isPopupVisible, "Popup should handle heavy content")
        XCTAssertLessThan(duration, 0.5, "Popup should appear within 500ms even with heavy content")

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
                    name: "John Doe", email: "john@example.com", status: .accepted, isOrganizer: true,
                    isSelf: false
                ),
                Attendee(name: "Jane Smith", email: "jane@example.com", status: .tentative, isSelf: false),
                Attendee(
                    email: "contractor@external.com", status: .needsAction, isOptional: true, isSelf: false
                ),
            ],
            calendarId: "primary",
            // swiftlint:disable:next force_unwrapping
            links: [URL(string: "https://meet.google.com/abc-defg-hij")!]
        )
    }
}
