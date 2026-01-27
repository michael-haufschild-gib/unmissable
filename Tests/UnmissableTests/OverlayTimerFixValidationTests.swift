import Combine
@testable import Unmissable
import XCTest

/// Test the fixed overlay timer logic without UI rendering
@MainActor
final class OverlayTimerFixValidationTests: XCTestCase {
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

        overlayManager = nil
        focusModeManager = nil
        mockPreferences = nil

        try await super.tearDown()
    }

    // MARK: - Timer Initialization Fix Validation

    func testTimerInitializesImmediately() async throws {
        // Test that the timer bug fix works: countdown should be set immediately, not after 1 second
        let futureTime = Date().addingTimeInterval(300) // 5 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        // Initial state should be 0
        XCTAssertEqual(overlayManager.timeUntilMeeting, 0, "Initial state should be 0")

        // Start countdown by showing overlay
        overlayManager.showOverlay(for: event)

        // Countdown should be set immediately (not 0 anymore)
        let immediateCountdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(immediateCountdown, 290, "Countdown should be set immediately")
        XCTAssertLessThan(immediateCountdown, 310, "Countdown should be reasonable")

        // Wait a short time and verify it's still working
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let afterWaitCountdown = overlayManager.timeUntilMeeting

        // Should still be approximately the same (minimal decrease)
        let difference = immediateCountdown - afterWaitCountdown
        XCTAssertGreaterThanOrEqual(difference, 0, "Countdown should not increase")
        XCTAssertLessThanOrEqual(difference, 0.2, "Change should be minimal over 0.1 seconds")
    }

    func testTimerUpdatesCorrectlyAfterInitialization() async throws {
        // Test that timer continues to update correctly after the immediate initialization
        let futureTime = Date().addingTimeInterval(180) // 3 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlay(for: event)

        // Get initial value (should be immediate)
        let initialCountdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(initialCountdown, 170, "Initial countdown should be ~3 minutes")

        // Wait for timer to update
        try await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 seconds

        let updatedCountdown = overlayManager.timeUntilMeeting
        XCTAssertLessThan(updatedCountdown, initialCountdown, "Timer should continue updating")

        let decrease = initialCountdown - updatedCountdown
        XCTAssertGreaterThan(decrease, 1.0, "Should decrease by approximately 1 second")
        XCTAssertLessThan(decrease, 1.5, "Should decrease by approximately 1 second")
    }

    func testMultipleEventsSwitchCorrectly() {
        // Test that switching events immediately updates the countdown (no delay)
        let event1 = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(120)) // 2 minutes
        let event2 = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(360)) // 6 minutes

        // Show first event
        overlayManager.showOverlay(for: event1)
        let countdown1 = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(countdown1, 110, "First event should have ~2 minutes")
        XCTAssertLessThan(countdown1, 130, "First event should have ~2 minutes")

        // Immediately switch to second event
        overlayManager.showOverlay(for: event2)
        let countdown2 = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(countdown2, 350, "Second event should have ~6 minutes")
        XCTAssertLessThan(countdown2, 370, "Second event should have ~6 minutes")

        // Should be immediate switch, not gradual
        XCTAssertGreaterThan(countdown2, countdown1 + 200, "Should be immediate jump to new countdown")
    }

    // MARK: - Event Data Accuracy Tests

    func testEventDataRemainsCorrectOverTime() async throws {
        // Test that event start/end times never change, only countdown changes
        let specificStart = Date().addingTimeInterval(240) // 4 minutes from now
        let specificEnd = specificStart.addingTimeInterval(1800) // 30 minute meeting

        let event = TestUtilities.createTestEvent(
            title: "Fixed Meeting",
            startDate: specificStart,
            endDate: specificEnd
        )

        overlayManager.showOverlay(for: event)

        // Check initial data
        XCTAssertEqual(
            overlayManager.activeEvent?.startDate, specificStart, "Start date should be correct"
        )
        XCTAssertEqual(overlayManager.activeEvent?.endDate, specificEnd, "End date should be correct")
        XCTAssertEqual(overlayManager.activeEvent?.title, "Fixed Meeting", "Title should be correct")

        // Wait and check data hasn't changed
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        XCTAssertEqual(
            overlayManager.activeEvent?.startDate, specificStart, "Start date should never change"
        )
        XCTAssertEqual(overlayManager.activeEvent?.endDate, specificEnd, "End date should never change")
        XCTAssertEqual(overlayManager.activeEvent?.title, "Fixed Meeting", "Title should never change")
    }

    func testCountdownCalculationAccuracy() {
        // Test that countdown calculation is always accurate to current time
        let testTime = Date().addingTimeInterval(90) // Exactly 90 seconds from now
        let event = TestUtilities.createTestEvent(startDate: testTime)

        overlayManager.showOverlay(for: event)

        // Countdown should be close to 90 seconds
        let countdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(countdown, 85, "Countdown should be close to 90 seconds")
        XCTAssertLessThan(countdown, 95, "Countdown should be close to 90 seconds")

        // Manual calculation should match
        let manualCountdown = testTime.timeIntervalSinceNow
        let difference = abs(countdown - manualCountdown)
        XCTAssertLessThan(difference, 0.1, "Overlay countdown should match manual calculation")
    }

    // MARK: - Timer Performance Tests

    func testTimerPerformanceIsConsistent() async throws {
        // Test that timer doesn't degrade over multiple updates
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        overlayManager.showOverlay(for: event)

        var measurements: [TimeInterval] = []

        // Take multiple timing measurements
        for i in 0 ..< 5 {
            let measureStart = Date()

            // Wait for a timer update
            try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

            let measureEnd = Date()
            let elapsed = measureEnd.timeIntervalSince(measureStart)
            measurements.append(elapsed)

            print("Timer update \(i + 1) took \(elapsed) seconds")
        }

        // All measurements should be close to 1.1 seconds
        for (index, measurement) in measurements.enumerated() {
            XCTAssertGreaterThan(measurement, 1.05, "Measurement \(index + 1) should be close to 1.1s")
            XCTAssertLessThan(measurement, 1.3, "Measurement \(index + 1) should be close to 1.1s")
        }

        // Consistency check (no significant drift)
        if measurements.count >= 2 {
            let firstMeasurement = measurements[0]
            let lastMeasurement = measurements[measurements.count - 1]
            let drift = abs(lastMeasurement - firstMeasurement)

            XCTAssertLessThan(drift, 0.2, "Timer should not drift significantly over time")
        }
    }

    // MARK: - Error Handling Tests

    func testPastEventHandling() {
        // Test that past events are handled correctly
        let pastEvent = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(-120)) // 2 minutes ago

        overlayManager.showOverlay(for: pastEvent)

        let countdown = overlayManager.timeUntilMeeting
        XCTAssertLessThan(countdown, 0, "Past events should have negative countdown")
        XCTAssertGreaterThan(countdown, -130, "Should be approximately -120 seconds")
    }

    func testExtremeTimeValues() {
        // Test handling of extreme time values

        // Very far future event (1 day from now)
        let farFutureEvent = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(86400))
        overlayManager.showOverlay(for: farFutureEvent)

        let farCountdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(farCountdown, 86300, "Should handle far future events")
        XCTAssertLessThan(farCountdown, 86500, "Should handle far future events")

        // Very recent past event (1 second ago)
        let recentPastEvent = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(-1))
        overlayManager.showOverlay(for: recentPastEvent)

        let recentCountdown = overlayManager.timeUntilMeeting
        XCTAssertLessThan(recentCountdown, 0, "Should handle recent past events")
        XCTAssertGreaterThan(recentCountdown, -5, "Should handle recent past events")
    }

    // MARK: - Memory Management Tests

    func testTimerCleanupOnHide() async throws {
        // Test that timer stops properly when overlay is hidden
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        overlayManager.showOverlay(for: event)

        // Let timer run briefly
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let runningCountdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(runningCountdown, 290, "Timer should be running")

        // Hide overlay
        overlayManager.hideOverlay()
        let hiddenCountdown = overlayManager.timeUntilMeeting

        // Wait and verify timer stopped
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        let afterWaitCountdown = overlayManager.timeUntilMeeting

        XCTAssertEqual(hiddenCountdown, afterWaitCountdown, "Timer should stop when overlay hidden")
    }
}
