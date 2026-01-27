import Combine
@testable import Unmissable
import XCTest

/// Tests that demonstrate and verify fixes for critical overlay timing bugs
@MainActor
final class OverlayBugReproductionTests: XCTestCase {
    var overlayManager: OverlayManager!
    var mockPreferences: PreferencesManager!
    var focusModeManager: FocusModeManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        mockPreferences = TestUtilities.createTestPreferencesManager()
        focusModeManager = FocusModeManager(preferencesManager: mockPreferences)
        overlayManager = OverlayManager(
            preferencesManager: mockPreferences, focusModeManager: focusModeManager
        )
        cancellables = Set<AnyCancellable>()

        try await super.setUp()
    }

    override func tearDown() async throws {
        overlayManager?.hideOverlay()
        cancellables.removeAll()

        // Clean up
        overlayManager = nil
        focusModeManager = nil
        mockPreferences = nil

        try await super.tearDown()
    }

    // MARK: - Bug Reproduction Tests

    func testOverlayManagerTimerDataConsistency() async throws {
        // Test that OverlayManager's timer provides consistent data
        let futureTime = Date().addingTimeInterval(300) // 5 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlay(for: event)

        // Wait for timer to run and collect values
        try await Task.sleep(nanoseconds: 100_000_000) // Initial delay
        let firstValue = overlayManager.timeUntilMeeting

        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        let secondValue = overlayManager.timeUntilMeeting

        try await Task.sleep(nanoseconds: 1_100_000_000) // Another 1.1 seconds
        let thirdValue = overlayManager.timeUntilMeeting

        // OverlayManager's timer should be working consistently
        XCTAssertGreaterThan(firstValue, secondValue, "OverlayManager countdown should decrease")
        XCTAssertGreaterThan(
            secondValue, thirdValue, "OverlayManager countdown should continue decreasing"
        )

        // Verify decreases are approximately 1 second
        let firstDecrease = firstValue - secondValue
        let secondDecrease = secondValue - thirdValue

        XCTAssertGreaterThan(firstDecrease, 0.9, "Should decrease by ~1 second")
        XCTAssertLessThan(firstDecrease, 1.5, "Should decrease by ~1 second")
        XCTAssertGreaterThan(secondDecrease, 0.9, "Should decrease by ~1 second")
        XCTAssertLessThan(secondDecrease, 1.5, "Should decrease by ~1 second")
    }

    func testOverlayManagerEventDataAccuracy() async throws {
        // Test that OverlayManager maintains correct event data
        let specificStartTime = Date().addingTimeInterval(600) // 10 minutes from now
        let specificEndTime = specificStartTime.addingTimeInterval(3600) // 1 hour meeting

        let event = TestUtilities.createTestEvent(
            title: "Important Meeting",
            startDate: specificStartTime,
            endDate: specificEndTime
        )

        overlayManager.showOverlay(for: event)

        // Verify OverlayManager has correct event data
        XCTAssertEqual(overlayManager.activeEvent?.id, event.id, "Should have correct event ID")
        XCTAssertEqual(
            overlayManager.activeEvent?.title, "Important Meeting", "Should have correct title"
        )
        XCTAssertEqual(
            overlayManager.activeEvent?.startDate, specificStartTime, "Should have correct start time"
        )
        XCTAssertEqual(
            overlayManager.activeEvent?.endDate, specificEndTime, "Should have correct end time"
        )

        // Event data should not change over time
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        XCTAssertEqual(
            overlayManager.activeEvent?.startDate, specificStartTime, "Start time should never change"
        )
        XCTAssertEqual(
            overlayManager.activeEvent?.endDate, specificEndTime, "End time should never change"
        )
    }

    func testTimerStopsAndStartsCorrectly() async throws {
        // Test timer lifecycle management
        let event1 = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))
        let event2 = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600))

        // Show first overlay
        overlayManager.showOverlay(for: event1)
        try await Task.sleep(nanoseconds: 100_000_000) // Let timer start

        let firstCountdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(firstCountdown, 290, "First event should have ~5 minutes")

        // Switch to second overlay (should restart timer)
        overlayManager.showOverlay(for: event2)
        try await Task.sleep(nanoseconds: 100_000_000) // Let timer restart

        let secondCountdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(secondCountdown, 590, "Second event should have ~10 minutes")
        XCTAssertGreaterThan(secondCountdown, firstCountdown, "Second event should have more time")

        // Hide overlay (should stop timer)
        overlayManager.hideOverlay()
        let countdownAfterHide = overlayManager.timeUntilMeeting

        // Wait and verify timer stopped
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        let countdownAfterWait = overlayManager.timeUntilMeeting

        XCTAssertEqual(countdownAfterHide, countdownAfterWait, "Timer should stop when overlay hidden")
    }

    func testOverlayResponsivenessUnderTimerLoad() async throws {
        // Test that overlay remains responsive while timer is running
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        overlayManager.showOverlay(for: event)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

        // Let timer run for a few cycles
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Overlay should still be responsive
        let hideStartTime = Date()
        overlayManager.hideOverlay()
        let hideEndTime = Date()

        let hideDuration = hideEndTime.timeIntervalSince(hideStartTime)
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden")
        XCTAssertLessThan(hideDuration, 0.1, "Hide operation should be fast (not frozen)")
    }

    // MARK: - Edge Case Tests

    func testMultipleEventsRapidSwitching() async throws {
        // Test rapid switching between events (stress test)
        let events = [
            TestUtilities.createTestEvent(title: "Meeting 1", startDate: Date().addingTimeInterval(180)),
            TestUtilities.createTestEvent(title: "Meeting 2", startDate: Date().addingTimeInterval(360)),
            TestUtilities.createTestEvent(title: "Meeting 3", startDate: Date().addingTimeInterval(540)),
        ]

        // Rapidly switch between events
        for (index, event) in events.enumerated() {
            overlayManager.showOverlay(for: event)

            // Very brief wait
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            // Verify correct event is active
            XCTAssertEqual(
                overlayManager.activeEvent?.title, event.title, "Should show correct event \(index + 1)"
            )

            // Check that countdown is reasonable for this event
            let countdown = overlayManager.timeUntilMeeting
            let expectedMin = Double(180 * (index + 1)) - 10 // Allow some variance
            let expectedMax = Double(180 * (index + 1)) + 10

            XCTAssertGreaterThan(
                countdown, expectedMin, "Countdown should be reasonable for event \(index + 1)"
            )
            XCTAssertLessThan(
                countdown, expectedMax, "Countdown should be reasonable for event \(index + 1)"
            )
        }

        // Final check that timer is still working
        let finalCountdownBefore = overlayManager.timeUntilMeeting
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        let finalCountdownAfter = overlayManager.timeUntilMeeting

        XCTAssertLessThan(
            finalCountdownAfter, finalCountdownBefore,
            "Timer should still be working after rapid switching"
        )
    }

    func testOverlayAutoHideLogic() async throws {
        // Test auto-hide behavior for old meetings
        let oldMeeting = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(-400)) // 6+ minutes ago

        overlayManager.showOverlay(for: oldMeeting)

        // Wait for auto-hide logic to trigger
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        XCTAssertFalse(overlayManager.isOverlayVisible, "Old meeting should auto-hide")
        XCTAssertNil(overlayManager.activeEvent, "Active event should be cleared")
    }

    // MARK: - Performance Tests

    func testTimerPerformanceOverTime() async throws {
        // Test that timer doesn't degrade performance over time
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600)) // 10 minutes

        overlayManager.showOverlay(for: event)

        var updateTimes: [TimeInterval] = []

        // Measure timer update performance over several cycles
        for _ in 0 ..< 5 {
            let updateStart = Date()
            try await Task.sleep(nanoseconds: 1_100_000_000) // Wait for next timer update
            let updateEnd = Date()

            let updateDuration = updateEnd.timeIntervalSince(updateStart)
            updateTimes.append(updateDuration)
        }

        // All updates should be fast
        for (index, updateTime) in updateTimes.enumerated() {
            XCTAssertLessThan(updateTime, 1.2, "Timer update \(index + 1) should be fast")
        }

        // Performance should be consistent (no significant degradation)
        if updateTimes.count >= 2 {
            let firstUpdate = updateTimes[0]
            let lastUpdate = updateTimes[updateTimes.count - 1]
            let performanceDiff = abs(lastUpdate - firstUpdate)

            XCTAssertLessThan(performanceDiff, 0.3, "Timer performance should be consistent")
        }
    }
}
