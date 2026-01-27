import Foundation
@testable import Unmissable
import XCTest

/// Test helpers specifically for timer migration validation
/// Ensures consistent testing patterns across all timer modernization phases
class TimerMigrationTestHelpers: XCTestCase {
    /// Standard timing tolerance for timer tests
    static let timingTolerance: TimeInterval = 0.1 // 100ms tolerance

    /// Extended tolerance for longer timers (>10 seconds)
    static let extendedTimingTolerance: TimeInterval = 1.0 // 1 second tolerance

    /// Memory leak detection timeout
    static let memoryLeakTimeout: TimeInterval = 2.0

    /// Create a test-safe preferences manager with known values
    @MainActor
    static func createTestPreferencesManager() -> PreferencesManager {
        let prefs = PreferencesManager()

        // Set known test values that don't conflict with migration
        prefs.defaultAlertMinutes = 2 // Use consistent test value
        prefs.useLengthBasedTiming = false
        prefs.shortMeetingAlertMinutes = 1
        prefs.mediumMeetingAlertMinutes = 3
        prefs.longMeetingAlertMinutes = 5
        // Note: soundEnabled is computed, cannot be set
        prefs.overlayOpacity = 0.8

        return prefs
    }

    /// Create a test event with predictable timing
    static func createTestEvent(
        minutesInFuture: Int = 5,
        title: String = "Timer Migration Test Event",
        id: String? = nil
    ) -> Event {
        let startDate = Date().addingTimeInterval(TimeInterval(minutesInFuture * 60))
        let endDate = startDate.addingTimeInterval(1800) // 30 minute meeting

        return Event(
            id: id ?? UUID().uuidString,
            title: title,
            startDate: startDate,
            endDate: endDate,
            organizer: "test@example.com",
            description: "Test event for timer migration validation",
            location: "Test Location",
            attendees: [],
            attachments: [],
            isAllDay: false,
            calendarId: "test-calendar",
            timezone: TimeZone.current.identifier,
            links: [],
            provider: nil,
            snoozeUntil: nil,
            autoJoinEnabled: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Validate timer accuracy within tolerance
    static func validateTimerAccuracy(
        expected: Date,
        actual: Date,
        tolerance: TimeInterval = timingTolerance,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let timingError = abs(actual.timeIntervalSince(expected))
        XCTAssertLessThanOrEqual(
            timingError,
            tolerance,
            "Timer accuracy exceeded tolerance: \(timingError)s > \(tolerance)s",
            file: file,
            line: line
        )
    }

    /// Create expectation with standard timeout for timer tests
    static func createTimerExpectation(
        description: String,
        timeout _: TimeInterval = 10.0
    ) -> XCTestExpectation {
        XCTestExpectation(description: description)
    }

    /// Wait for expectations with timer-appropriate timeout
    static func waitForTimerExpectations(
        _ expectations: [XCTestExpectation],
        timeout: TimeInterval = 10.0,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let result = XCTWaiter.wait(for: expectations, timeout: timeout)
        switch result {
        case .completed:
            break
        case .timedOut:
            XCTFail("Timer expectation timed out after \(timeout)s", file: file, line: line)
        case .incorrectOrder:
            XCTFail("Timer expectations completed in incorrect order", file: file, line: line)
        case .invertedFulfillment:
            XCTFail("Timer expectation fulfilled when it should not have been", file: file, line: line)
        case .interrupted:
            XCTFail("Timer expectation was interrupted", file: file, line: line)
        @unknown default:
            XCTFail("Unknown timer expectation result", file: file, line: line)
        }
    }

    /// Log timing metrics for performance analysis
    static func logTimingMetrics(
        operation: String,
        expected: Date,
        actual: Date,
        tolerance: TimeInterval
    ) {
        let error = actual.timeIntervalSince(expected)
        let accuracy = abs(error)
        let successRate = 1.0 - (accuracy / tolerance)

        print("⏱️ TIMING METRICS:")
        print("   Operation: \(operation)")
        print("   Expected: \(expected)")
        print("   Actual: \(actual)")
        print("   Error: \(error)s")
        print("   Accuracy: \(accuracy)s")
        print("   Success Rate: \(String(format: "%.1f", successRate * 100))%")
        print("   Within Tolerance: \(accuracy <= tolerance ? "✅" : "❌")")
    }

    /// Memory pressure simulation for testing Task-based timers under load
    static func simulateMemoryPressure(
        timerCount: Int = 100,
        duration: TimeInterval = 5.0
    ) async {
        print("💾 MEMORY PRESSURE: Creating \(timerCount) timers for \(duration)s")

        var tasks: [Task<Void, Never>] = []

        for _ in 0 ..< timerCount {
            let task = Task {
                do {
                    try await Task.sleep(for: .seconds(duration))
                } catch {
                    // Task cancelled
                }
            }
            tasks.append(task)
        }

        // Let them run briefly
        try? await Task.sleep(for: .milliseconds(100))

        // Cancel all
        for task in tasks {
            task.cancel()
        }

        print("💾 MEMORY PRESSURE: Cleaned up \(timerCount) timers")
    }
}

// MARK: - Timer Type Specific Helpers

extension TimerMigrationTestHelpers {
    /// Helpers specific to countdown timer testing
    enum CountdownTimer {
        static let updateInterval: TimeInterval = 1.0
        static let tolerance: TimeInterval = 0.05 // 50ms for 1-second updates

        static func validateCountdownAccuracy(
            iterations: Int,
            actualDuration: TimeInterval,
            file: StaticString = #file,
            line: UInt = #line
        ) {
            let expectedDuration = TimeInterval(iterations) * updateInterval
            let error = abs(actualDuration - expectedDuration)
            XCTAssertLessThanOrEqual(
                error,
                tolerance * Double(iterations),
                "Countdown timer drift exceeded tolerance over \(iterations) iterations",
                file: file,
                line: line
            )
        }
    }

    /// Helpers specific to snooze timer testing
    enum SnoozeTimer {
        static let tolerance: TimeInterval = 1.0 // 1 second for longer delays

        static func createSnoozeTestEvent(snoozeMinutes _: Int = 5) -> Event {
            // Create event that "already happened" so we can test snooze
            _ = Date().addingTimeInterval(-300) // 5 minutes ago
            return createTestEvent(minutesInFuture: -5, title: "Snooze Test Event")
        }
    }

    /// Helpers specific to schedule timer testing
    enum ScheduleTimer {
        static let tolerance: TimeInterval = 1.0 // 1 second for scheduling accuracy

        static func validateSchedulingAccuracy(
            events _: [Event],
            expectedTriggers: [Date],
            actualTriggers: [Date],
            file: StaticString = #file,
            line: UInt = #line
        ) {
            XCTAssertEqual(
                expectedTriggers.count,
                actualTriggers.count,
                "Mismatch in trigger count",
                file: file,
                line: line
            )

            for (expected, actual) in zip(expectedTriggers, actualTriggers) {
                validateTimerAccuracy(
                    expected: expected,
                    actual: actual,
                    tolerance: tolerance,
                    file: file,
                    line: line
                )
            }
        }
    }
}
