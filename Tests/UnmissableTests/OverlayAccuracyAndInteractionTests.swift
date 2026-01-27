import Combine
@testable import Unmissable
import XCTest

/// Comprehensive tests for overlay display accuracy and interaction functionality
/// Tests critical bugs: wrong start time, wrong countdown, non-functioning timer, frozen overlay
@MainActor
final class OverlayAccuracyAndInteractionTests: XCTestCase {
    var overlayManager: OverlayManager!
    var mockPreferences: PreferencesManager!
    var focusModeManager: FocusModeManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        mockPreferences = TestUtilities.createTestPreferencesManager()
        focusModeManager = FocusModeManager(preferencesManager: mockPreferences)
        overlayManager = OverlayManager(
            preferencesManager: mockPreferences,
            focusModeManager: focusModeManager,
            isTestMode: true // CRITICAL FIX: Prevent UI creation in tests
        )
        cancellables = Set<AnyCancellable>()

        try await super.setUp()
    }

    override func tearDown() async throws {
        overlayManager.hideOverlay()
        cancellables.removeAll()

        // Give UI components time to clean up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        overlayManager = nil
        focusModeManager = nil
        mockPreferences = nil

        try await super.tearDown()
    }

    // MARK: - Start Time Display Tests

    func testOverlayDisplaysCorrectStartTime() async throws {
        // Test that overlay shows the exact event start time, not the current time
        let specificStartTime = Date().addingTimeInterval(600) // 10 minutes from now
        let event = TestUtilities.createTestEvent(
            title: "Test Meeting",
            startDate: specificStartTime,
            endDate: specificStartTime.addingTimeInterval(3600) // 1 hour
        )

        // Show overlay
        overlayManager.showOverlay(for: event)

        // Verify overlay is visible and has correct event
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")
        XCTAssertEqual(
            overlayManager.activeEvent?.id, event.id, "Overlay should display the correct event"
        )
        XCTAssertEqual(
            overlayManager.activeEvent?.startDate, specificStartTime,
            "Overlay should show correct start time"
        )

        // Wait a moment and verify start time hasn't changed
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        XCTAssertEqual(
            overlayManager.activeEvent?.startDate, specificStartTime, "Start time should remain constant"
        )
    }

    func testMultipleEventsShowCorrectStartTimes() {
        // Test that switching between events shows correct start times for each
        let firstEventTime = Date().addingTimeInterval(300) // 5 minutes from now
        let secondEventTime = Date().addingTimeInterval(900) // 15 minutes from now

        let firstEvent = TestUtilities.createTestEvent(
            title: "First Meeting", startDate: firstEventTime
        )
        let secondEvent = TestUtilities.createTestEvent(
            title: "Second Meeting", startDate: secondEventTime
        )

        // Show first event
        overlayManager.showOverlay(for: firstEvent)
        XCTAssertEqual(
            overlayManager.activeEvent?.startDate, firstEventTime, "Should show first event time"
        )

        // Switch to second event
        overlayManager.showOverlay(for: secondEvent)
        XCTAssertEqual(
            overlayManager.activeEvent?.startDate, secondEventTime, "Should show second event time"
        )

        // Switch back to first event
        overlayManager.showOverlay(for: firstEvent)
        XCTAssertEqual(
            overlayManager.activeEvent?.startDate, firstEventTime, "Should show first event time again"
        )
    }

    // MARK: - Countdown Timer Accuracy Tests

    func testCountdownTimerShowsCorrectRemainingTime() async throws {
        // Test that countdown shows accurate time remaining until meeting starts
        let futureTime = Date().addingTimeInterval(120) // Exactly 2 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        // Show overlay
        overlayManager.showOverlay(for: event)

        // Wait for timer to initialize
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // Check initial countdown is approximately 2 minutes (allow small variance for processing time)
        let initialCountdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(initialCountdown, 115, "Initial countdown should be close to 2 minutes")
        XCTAssertLessThan(initialCountdown, 125, "Initial countdown should be close to 2 minutes")

        // Wait 1 second and verify countdown decreased
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

        let updatedCountdown = overlayManager.timeUntilMeeting
        XCTAssertLessThan(updatedCountdown, initialCountdown, "Countdown should decrease over time")
        XCTAssertGreaterThan(
            initialCountdown - updatedCountdown, 0.9, "Should decrease by approximately 1 second"
        )
        XCTAssertLessThan(
            initialCountdown - updatedCountdown, 1.5, "Should decrease by approximately 1 second"
        )
    }

    func testCountdownTimerUpdatesEverySecond() async throws {
        // Test that countdown timer actually updates every second consistently
        let futureTime = Date().addingTimeInterval(300) // 5 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlay(for: event)

        // Record multiple countdown values over time
        var countdownValues: [TimeInterval] = []

        for _ in 0 ..< 3 {
            countdownValues.append(overlayManager.timeUntilMeeting)
            try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        }

        // Verify countdown is decreasing consistently
        XCTAssertGreaterThan(countdownValues.count, 2, "Should have multiple readings")

        for i in 1 ..< countdownValues.count {
            let decrease = countdownValues[i - 1] - countdownValues[i]
            XCTAssertGreaterThan(decrease, 0.9, "Countdown should decrease by ~1 second between readings")
            XCTAssertLessThan(decrease, 1.5, "Countdown should decrease by ~1 second between readings")
        }
    }

    func testCountdownTimerHandlesPastEvents() async throws {
        // Test countdown behavior when event has already started
        let pastTime = Date().addingTimeInterval(-60) // 1 minute ago
        let event = TestUtilities.createTestEvent(startDate: pastTime)

        overlayManager.showOverlay(for: event)
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // Countdown should be negative (meeting already started)
        XCTAssertLessThan(
            overlayManager.timeUntilMeeting, 0, "Countdown should be negative for past events"
        )
        XCTAssertGreaterThan(
            overlayManager.timeUntilMeeting, -70, "Should be approximately -60 seconds"
        )
    }

    // MARK: - Timer Functionality Tests

    func testCountdownTimerActuallyRuns() async throws {
        // Test that the timer is actually running and not frozen
        let futureTime = Date().addingTimeInterval(180) // 3 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlay(for: event)

        // Get initial value
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let initialTime = overlayManager.timeUntilMeeting

        // Wait and check for change
        try await Task.sleep(nanoseconds: 2_100_000_000) // 2.1 seconds
        let updatedTime = overlayManager.timeUntilMeeting

        XCTAssertNotEqual(initialTime, updatedTime, "Timer should be running and values should change")
        XCTAssertLessThan(updatedTime, initialTime, "Time should be decreasing")

        // Verify it's still running after longer wait
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        let finalTime = overlayManager.timeUntilMeeting

        XCTAssertLessThan(finalTime, updatedTime, "Timer should continue running")
    }

    func testTimerStopsWhenOverlayHidden() async throws {
        // Test that timer stops when overlay is hidden (prevents memory leaks)
        let futureTime = Date().addingTimeInterval(300) // 5 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlay(for: event)
        try await Task.sleep(nanoseconds: 100_000_000) // Let timer start

        // Hide overlay
        overlayManager.hideOverlay()

        // Get value after hiding
        let timeAfterHide = overlayManager.timeUntilMeeting

        // Wait and verify value doesn't change (timer stopped)
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        let timeAfterWait = overlayManager.timeUntilMeeting

        XCTAssertEqual(timeAfterHide, timeAfterWait, "Timer should stop when overlay is hidden")
    }

    func testTimerRestartsProperly() async throws {
        // Test that timer can be stopped and started correctly
        let firstEvent = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))
        let secondEvent = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600))

        // Show first event
        overlayManager.showOverlay(for: firstEvent)
        try await Task.sleep(nanoseconds: 100_000_000)
        let firstEventTime = overlayManager.timeUntilMeeting

        // Switch to second event (should restart timer)
        overlayManager.showOverlay(for: secondEvent)
        try await Task.sleep(nanoseconds: 100_000_000)
        let secondEventTime = overlayManager.timeUntilMeeting

        XCTAssertGreaterThan(
            secondEventTime, firstEventTime, "Second event should have more time remaining"
        )

        // Verify timer is running for second event
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        let updatedSecondEventTime = overlayManager.timeUntilMeeting

        XCTAssertLessThan(
            updatedSecondEventTime, secondEventTime, "Timer should be running for second event"
        )
    }

    // MARK: - Overlay Interaction Tests

    func testOverlayRemainsInteractive() async throws {
        // Test that overlay doesn't freeze and can be interacted with
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        overlayManager.showOverlay(for: event)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

        // Wait for timer to run
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Overlay should still be responsive (can be hidden)
        overlayManager.hideOverlay()
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hideable (not frozen)")
    }

    func testOverlayResponseTimeIsReasonable() async throws {
        // Test that overlay responds to commands quickly (not frozen/laggy)
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        let showStartTime = Date()
        overlayManager.showOverlay(for: event)
        let showEndTime = Date()

        let showDuration = showEndTime.timeIntervalSince(showStartTime)
        XCTAssertLessThan(showDuration, 0.5, "Overlay should show quickly (not frozen)")

        // Wait for timer to run
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        let hideStartTime = Date()
        overlayManager.hideOverlay()
        let hideEndTime = Date()

        let hideDuration = hideEndTime.timeIntervalSince(hideStartTime)
        XCTAssertLessThan(hideDuration, 0.5, "Overlay should hide quickly (not frozen)")
    }

    // MARK: - Integration Tests

    func testOverlayManagerTimerSynchronization() async throws {
        // Test that OverlayManager's computed timeUntilMeeting decreases over time
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(240)) // 4 minutes

        var collectedValues: [TimeInterval] = []

        overlayManager.showOverlay(for: event)

        // Collect values at intervals
        for _ in 0 ..< 3 {
            collectedValues.append(overlayManager.timeUntilMeeting)
            try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        }
        collectedValues.append(overlayManager.timeUntilMeeting)

        // Verify collected values are decreasing (timer working)
        XCTAssertGreaterThan(collectedValues.count, 2, "Should have multiple collected values")

        if collectedValues.count >= 3 {
            XCTAssertGreaterThan(
                collectedValues[0], collectedValues[1], "Collected values should decrease"
            )
            XCTAssertGreaterThan(
                collectedValues[1], collectedValues[2], "Collected values should decrease"
            )
        }
    }

    func testTimerAccuracyOverLongerPeriod() async throws {
        // Test timer accuracy over a longer period to catch drift issues
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600)) // 10 minutes

        overlayManager.showOverlay(for: event)

        // Record initial time
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let startTime = Date()
        let initialCountdown = overlayManager.timeUntilMeeting

        // Wait 5 seconds
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        let endTime = Date()
        let finalCountdown = overlayManager.timeUntilMeeting

        let actualElapsed = endTime.timeIntervalSince(startTime)
        let countdownDecrease = initialCountdown - finalCountdown

        // Countdown decrease should match actual elapsed time (within reasonable tolerance)
        let difference = abs(actualElapsed - countdownDecrease)
        XCTAssertLessThan(difference, 0.5, "Timer should be accurate over longer periods")
    }

    // MARK: - Edge Cases

    func testZeroTimeRemainingHandled() async throws {
        // Test behavior when exactly at meeting start time
        let exactStartTime = Date().addingTimeInterval(1) // 1 second from now
        let event = TestUtilities.createTestEvent(startDate: exactStartTime)

        overlayManager.showOverlay(for: event)

        // Wait for countdown to reach zero and go negative
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        XCTAssertLessThan(overlayManager.timeUntilMeeting, 1, "Should handle zero/negative time")
        XCTAssertTrue(
            overlayManager.isOverlayVisible, "Overlay should still be visible briefly after start"
        )
    }

    func testAutoHideAfterMeetingStarts() async throws {
        // Test that overlay auto-hides after meeting has been running for a while
        let pastTime = Date().addingTimeInterval(-400) // Meeting started 6+ minutes ago
        let event = TestUtilities.createTestEvent(startDate: pastTime)

        overlayManager.showOverlay(for: event)

        // Wait for auto-hide logic to trigger
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should auto-hide for old meetings")
    }
}
