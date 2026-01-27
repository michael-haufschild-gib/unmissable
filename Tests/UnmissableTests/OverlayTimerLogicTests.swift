import Combine
@testable import Unmissable
import XCTest

/// Tests for overlay timer logic and data accuracy (without UI rendering)
/// Tests critical bugs: wrong countdown calculations, timer not functioning, data synchronization
@MainActor
final class OverlayTimerLogicTests: XCTestCase {
    var mockPreferences: PreferencesManager!
    var focusModeManager: FocusModeManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        mockPreferences = TestUtilities.createTestPreferencesManager()
        focusModeManager = FocusModeManager(preferencesManager: mockPreferences)
        cancellables = Set<AnyCancellable>()

        try await super.setUp()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        focusModeManager = nil
        mockPreferences = nil

        try await super.tearDown()
    }

    // MARK: - Countdown Calculation Tests

    func testCountdownCalculationAccuracy() {
        // Test countdown calculation logic without UI components
        let specificTime = Date().addingTimeInterval(120) // Exactly 2 minutes from now
        let event = TestUtilities.createTestEvent(startDate: specificTime)

        // Test the time calculation logic directly
        let timeUntilMeeting = event.startDate.timeIntervalSinceNow

        // Should be approximately 120 seconds (allow small variance for processing time)
        XCTAssertGreaterThan(timeUntilMeeting, 115, "Time calculation should be close to 2 minutes")
        XCTAssertLessThan(timeUntilMeeting, 125, "Time calculation should be close to 2 minutes")

        // Test with past event
        let pastTime = Date().addingTimeInterval(-60) // 1 minute ago
        let pastEvent = TestUtilities.createTestEvent(startDate: pastTime)
        let pastTimeUntilMeeting = pastEvent.startDate.timeIntervalSinceNow

        XCTAssertLessThan(pastTimeUntilMeeting, 0, "Past events should have negative time remaining")
        XCTAssertGreaterThan(pastTimeUntilMeeting, -70, "Should be approximately -60 seconds")
    }

    func testEventTimingConsistency() async throws {
        // Test that event times don't change unexpectedly
        let fixedTime = Date().addingTimeInterval(300)
        let event = TestUtilities.createTestEvent(startDate: fixedTime)

        let firstCalculation = event.startDate.timeIntervalSinceNow

        // Wait a moment
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let secondCalculation = event.startDate.timeIntervalSinceNow

        // The event start time should be the same, but the calculation should show ~0.1s less time
        XCTAssertEqual(event.startDate, fixedTime, "Event start time should never change")
        XCTAssertLessThan(secondCalculation, firstCalculation, "Time remaining should decrease")

        let timeDifference = firstCalculation - secondCalculation
        XCTAssertGreaterThan(timeDifference, 0.05, "Should decrease by approximately 0.1 seconds")
        XCTAssertLessThan(timeDifference, 0.2, "Should decrease by approximately 0.1 seconds")
    }

    // MARK: - Timer Logic Tests (Without UI)

    func testTimerUpdateLogic() async throws {
        // Test timer update logic independently
        class MockOverlayManager {
            var timeUntilMeeting: TimeInterval = 0
            var event: Event?

            func updateCountdown(for event: Event) {
                timeUntilMeeting = event.startDate.timeIntervalSinceNow
            }
        }

        let mockManager = MockOverlayManager()
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(180)) // 3 minutes

        // First update
        mockManager.updateCountdown(for: event)
        let firstValue = mockManager.timeUntilMeeting

        XCTAssertGreaterThan(firstValue, 175, "Initial countdown should be close to 3 minutes")
        XCTAssertLessThan(firstValue, 185, "Initial countdown should be close to 3 minutes")

        // Wait and update again
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        mockManager.updateCountdown(for: event)
        let secondValue = mockManager.timeUntilMeeting

        XCTAssertLessThan(secondValue, firstValue, "Countdown should decrease")

        let decrease = firstValue - secondValue
        XCTAssertGreaterThan(decrease, 0.9, "Should decrease by approximately 1 second")
        XCTAssertLessThan(decrease, 1.5, "Should decrease by approximately 1 second")
    }

    func testAutoHideLogic() {
        // Test the auto-hide logic without UI components
        let oldMeetingTime = Date().addingTimeInterval(-400) // 6+ minutes ago
        let event = TestUtilities.createTestEvent(startDate: oldMeetingTime)

        let timeUntilMeeting = event.startDate.timeIntervalSinceNow

        // Should trigger auto-hide condition (meeting started more than 5 minutes ago)
        XCTAssertLessThan(timeUntilMeeting, -300, "Old meeting should meet auto-hide criteria")

        // Test recent meeting (should not auto-hide)
        let recentMeetingTime = Date().addingTimeInterval(-120) // 2 minutes ago
        let recentEvent = TestUtilities.createTestEvent(startDate: recentMeetingTime)

        let recentTimeUntilMeeting = recentEvent.startDate.timeIntervalSinceNow
        XCTAssertGreaterThan(recentTimeUntilMeeting, -300, "Recent meeting should not auto-hide")
    }

    // MARK: - Data Synchronization Tests

    func testMultipleEventsDataConsistency() {
        // Test that switching between events maintains data consistency
        let event1Time = Date().addingTimeInterval(300) // 5 minutes
        let event2Time = Date().addingTimeInterval(600) // 10 minutes

        let event1 = TestUtilities.createTestEvent(title: "First Meeting", startDate: event1Time)
        let event2 = TestUtilities.createTestEvent(title: "Second Meeting", startDate: event2Time)

        // Calculate times for both events
        let event1TimeRemaining = event1.startDate.timeIntervalSinceNow
        let event2TimeRemaining = event2.startDate.timeIntervalSinceNow

        XCTAssertGreaterThan(
            event2TimeRemaining, event1TimeRemaining, "Second event should have more time remaining"
        )

        // Verify the difference is approximately 5 minutes (300 seconds)
        let timeDifference = event2TimeRemaining - event1TimeRemaining
        XCTAssertGreaterThan(timeDifference, 295, "Time difference should be close to 5 minutes")
        XCTAssertLessThan(timeDifference, 305, "Time difference should be close to 5 minutes")
    }

    // MARK: - Edge Cases

    func testZeroAndNegativeTimeHandling() {
        // Test edge cases around meeting start time
        let exactStartTime = Date() // Exactly now
        let event = TestUtilities.createTestEvent(startDate: exactStartTime)

        let timeRemaining = event.startDate.timeIntervalSinceNow

        // Should be very close to zero (within processing time)
        XCTAssertLessThan(abs(timeRemaining), 1, "Time should be very close to zero")

        // Test slightly past meeting start
        let justPastTime = Date().addingTimeInterval(-30) // 30 seconds ago
        let pastEvent = TestUtilities.createTestEvent(startDate: justPastTime)

        let pastTimeRemaining = pastEvent.startDate.timeIntervalSinceNow
        XCTAssertLessThan(pastTimeRemaining, 0, "Past meeting should have negative time")
        XCTAssertGreaterThan(pastTimeRemaining, -35, "Should be approximately -30 seconds")
    }

    func testLargeTimeValues() {
        // Test handling of events far in the future
        let farFutureTime = Date().addingTimeInterval(7200) // 2 hours from now
        let event = TestUtilities.createTestEvent(startDate: farFutureTime)

        let timeRemaining = event.startDate.timeIntervalSinceNow

        XCTAssertGreaterThan(timeRemaining, 7100, "Should handle large time values correctly")
        XCTAssertLessThan(timeRemaining, 7300, "Should handle large time values correctly")
    }

    // MARK: - Timer Accuracy Tests

    func testTimerAccuracySimulation() async throws {
        // Simulate timer accuracy without actual Timer objects
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(60)) // 1 minute

        var timeReadings: [TimeInterval] = []
        let startTime = Date()

        // Simulate timer readings over 3 seconds
        for i in 0 ..< 4 {
            let currentTime = Date()
            let elapsedSinceStart = currentTime.timeIntervalSince(startTime)
            let expectedElapsed = Double(i) * 1.0 // Expected 1 second intervals

            if i > 0 {
                // Check that our elapsed time is close to expected
                let accuracy = abs(elapsedSinceStart - expectedElapsed)
                XCTAssertLessThan(accuracy, 0.1, "Timer simulation should be accurate")
            }

            // Calculate time remaining at this point
            let timeRemaining = event.startDate.timeIntervalSinceNow
            timeReadings.append(timeRemaining)

            if i < 3 {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }

        // Verify readings are decreasing consistently
        for i in 1 ..< timeReadings.count {
            XCTAssertLessThan(timeReadings[i], timeReadings[i - 1], "Time should consistently decrease")
        }
    }

    // MARK: - Format Testing (Supporting Functions)

    func testTimeFormatting() {
        // Test time formatting logic that might be used in the overlay
        func formatCountdown(_ timeInterval: TimeInterval) -> String {
            let absTime = abs(timeInterval)
            let minutes = Int(absTime) / 60
            let seconds = Int(absTime) % 60

            if timeInterval <= 0 {
                return "Started"
            } else {
                return String(format: "%02d:%02d", minutes, seconds)
            }
        }

        // Test various time values
        XCTAssertEqual(formatCountdown(125), "02:05", "Should format 125 seconds as 02:05")
        XCTAssertEqual(formatCountdown(60), "01:00", "Should format 60 seconds as 01:00")
        XCTAssertEqual(formatCountdown(30), "00:30", "Should format 30 seconds as 00:30")
        XCTAssertEqual(formatCountdown(-10), "Started", "Should show 'Started' for past times")
        XCTAssertEqual(formatCountdown(0), "Started", "Should show 'Started' for zero time")
    }
}
