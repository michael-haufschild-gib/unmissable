import Combine
@testable import Unmissable
import XCTest

/// Simple test to validate the OverlayManager timer initialization fix
@MainActor
final class OverlayManagerTimerFixTest: XCTestCase {
    var overlayManager: OverlayManager!
    var mockPreferences: PreferencesManager!

    override func setUp() async throws {
        mockPreferences = TestUtilities.createTestPreferencesManager()
        // Create OverlayManager without focus mode to avoid dependencies
        overlayManager = OverlayManager(
            preferencesManager: mockPreferences,
            focusModeManager: nil,
            isTestMode: true
        )

        try await super.setUp()
    }

    override func tearDown() async throws {
        overlayManager?.hideOverlay()
        overlayManager = nil
        mockPreferences = nil

        try await super.tearDown()
    }

    func testTimerInitializationFix() {
        // Test that the timer initialization bug is fixed
        let futureTime = Date().addingTimeInterval(300) // 5 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        // Start the overlay - this should immediately set the countdown
        overlayManager.showOverlay(for: event)

        // The fix should mean that timeUntilMeeting is set immediately, not 0
        XCTAssertGreaterThan(
            overlayManager.timeUntilMeeting, 290, "Timer should be initialized immediately"
        )
        XCTAssertLessThan(overlayManager.timeUntilMeeting, 310, "Timer should be reasonable")

        print("✅ Timer initialization fix working - countdown set immediately")
    }

    func testTimerUpdatesAfterInitialization() async throws {
        // Test that timer continues to work after initialization
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(120))

        overlayManager.showOverlay(for: event)
        let initialCountdown = overlayManager.timeUntilMeeting

        // Wait ~1.2 seconds to ensure at least one countdown tick in async environment
        try await Task.sleep(nanoseconds: 1_200_000_000)

        let updatedCountdown = overlayManager.timeUntilMeeting

        XCTAssertLessThan(updatedCountdown, initialCountdown, "Timer should continue to update")

        let decrease = initialCountdown - updatedCountdown
        XCTAssertGreaterThanOrEqual(decrease, 0.8, "Should decrease by ~1 second")
        XCTAssertLessThanOrEqual(decrease, 1.8, "Should decrease by ~1 second")

        print("✅ Timer continues to update correctly after initialization")
    }
}
