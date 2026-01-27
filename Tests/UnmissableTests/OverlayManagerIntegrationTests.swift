@testable import Unmissable
import XCTest

@MainActor
final class OverlayManagerIntegrationTests: XCTestCase {
    var overlayManager: OverlayManager!
    var preferencesManager: PreferencesManager!
    var focusModeManager: FocusModeManager!

    override func setUp() async throws {
        try await super.setUp()
        preferencesManager = PreferencesManager()
        focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager
        )
    }

    override func tearDown() async throws {
        overlayManager.hideOverlay()
        overlayManager = nil
        preferencesManager = nil
        focusModeManager = nil
        try await super.tearDown()
    }

    func testShowOverlayDoesNotCrash() {
        let event = createTestEvent()

        // This should not crash or cause infinite loops
        overlayManager.showOverlay(for: event)

        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, event.id)

        // Clean up
        overlayManager.hideOverlay()
        XCTAssertFalse(overlayManager.isOverlayVisible)
    }

    func testSnoozeOverlayDoesNotCauseInfiniteLoop() {
        let event = createTestEvent()

        // Show overlay first
        overlayManager.showOverlay(for: event)
        XCTAssertTrue(overlayManager.isOverlayVisible)

        // Snooze should hide the overlay and schedule properly
        overlayManager.snoozeOverlay(for: 1) // 1 minute snooze

        // Overlay should be hidden after snooze
        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    func testHideOverlayCleanupsProperly() {
        let event = createTestEvent()

        // Show overlay
        overlayManager.showOverlay(for: event)
        XCTAssertTrue(overlayManager.isOverlayVisible)

        // Hide overlay
        overlayManager.hideOverlay()

        // Verify cleanup
        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
        XCTAssertEqual(overlayManager.timeUntilMeeting, 0)
    }

    func testMultipleShowCallsDoNotAccumulate() {
        let event1 = createTestEvent(id: "event1", title: "First Event")
        let event2 = createTestEvent(id: "event2", title: "Second Event")

        // Show first overlay
        overlayManager.showOverlay(for: event1)
        XCTAssertEqual(overlayManager.activeEvent?.id, "event1")

        // Show second overlay - should replace first
        overlayManager.showOverlay(for: event2)
        XCTAssertEqual(overlayManager.activeEvent?.id, "event2")

        // Should still have only one overlay
        XCTAssertTrue(overlayManager.isOverlayVisible)
    }

    func testSnoozeWithoutActiveEventDoesNotCrash() {
        // Snoozing without an active event should not crash
        overlayManager.snoozeOverlay(for: 5)

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    // MARK: - Helper Methods

    private func createTestEvent(id: String = "test-event", title: String = "Test Meeting") -> Event {
        Event(
            id: id,
            title: title,
            startDate: Date().addingTimeInterval(300), // 5 minutes from now
            endDate: Date().addingTimeInterval(1800), // 30 minutes from now
            organizer: "test@example.com",
            calendarId: "test-calendar"
        )
    }
}
