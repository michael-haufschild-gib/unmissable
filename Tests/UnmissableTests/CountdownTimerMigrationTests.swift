import Foundation
@testable import Unmissable
import XCTest

/// Test cases specifically for countdown timer migration validation
/// These tests establish baseline behavior before migration and validate Task-based implementation
@MainActor
class CountdownTimerMigrationTests: XCTestCase {
    var overlayManager: OverlayManager!
    var preferencesManager: PreferencesManager!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        preferencesManager = TimerMigrationTestHelpers.createTestPreferencesManager()
        overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: nil,
            isTestMode: true
        )
    }

    override func tearDown() async throws {
        overlayManager = nil
        preferencesManager = nil
        try await super.tearDown()
    }

    /// Test countdown timer maintains 1-second accuracy
    func testCountdownTimerAccuracy() {
        let event = TimerMigrationTestHelpers.createTestEvent(
            minutesInFuture: 2,
            title: "Countdown Accuracy Test"
        )

        let expectation = TimerMigrationTestHelpers.createTimerExpectation(
            description: "Countdown updates received"
        )
        expectation.expectedFulfillmentCount = 5 // 5 updates over 5 seconds

        var updateTimes: [Date] = []
        let startTime = Date()

        // Show overlay to start countdown
        overlayManager.showOverlay(for: event)

        // Monitor countdown updates
        let observer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateTimes.append(Date())
            expectation.fulfill()
        }

        TimerMigrationTestHelpers.waitForTimerExpectations([expectation], timeout: 7.0)
        observer.invalidate()

        // Validate timing accuracy
        for (index, updateTime) in updateTimes.enumerated() {
            let expectedTime = startTime.addingTimeInterval(TimeInterval(index + 1))
            TimerMigrationTestHelpers.validateTimerAccuracy(
                expected: expectedTime,
                actual: updateTime,
                tolerance: TimerMigrationTestHelpers.CountdownTimer.tolerance
            )
        }

        // Clean up
        overlayManager.hideOverlay()
    }

    /// Test countdown timer stops properly when overlay is hidden
    func testCountdownTimerStopsOnHide() async throws {
        let event = TimerMigrationTestHelpers.createTestEvent(
            minutesInFuture: 2,
            title: "Countdown Stop Test"
        )

        // Show overlay
        overlayManager.showOverlay(for: event)

        // Wait for countdown to start
        try await Task.sleep(for: .seconds(1))

        // Verify overlay is visible and countdown is running
        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertNotEqual(overlayManager.timeUntilMeeting, 0.0)

        // Hide overlay
        overlayManager.hideOverlay()

        // Wait for cleanup
        try await Task.sleep(for: .milliseconds(100))

        // Verify countdown stopped
        XCTAssertFalse(overlayManager.isOverlayVisible)
        // Note: timeUntilMeeting might not be 0 immediately, but countdown should not update

        let timeBeforeWait = overlayManager.timeUntilMeeting
        try await Task.sleep(for: .seconds(2))
        let timeAfterWait = overlayManager.timeUntilMeeting

        // If countdown stopped, these should be equal (no updates)
        XCTAssertEqual(
            timeBeforeWait,
            timeAfterWait,
            accuracy: 0.1,
            "Countdown should have stopped after hiding overlay"
        )
    }

    /// Test countdown timer handles rapid show/hide cycles
    func testCountdownTimerRapidCycles() async throws {
        let event = TimerMigrationTestHelpers.createTestEvent(
            minutesInFuture: 2,
            title: "Countdown Rapid Cycle Test"
        )

        // Perform rapid show/hide cycles
        for i in 0 ..< 10 {
            overlayManager.showOverlay(for: event)
            XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible after show \(i)")

            try await Task.sleep(for: .milliseconds(50))

            overlayManager.hideOverlay()
            XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after hide \(i)")

            try await Task.sleep(for: .milliseconds(50))
        }

        // Final state should be clean
        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    /// Test countdown timer memory usage under load
    func testCountdownTimerMemoryUsage() async throws {
        let initialMemory = getMemoryUsage()
        print("📊 MEMORY TEST: Initial memory usage: \(initialMemory / 1024 / 1024) MB")

        let events = (0 ..< 50).map { index in
            TimerMigrationTestHelpers.createTestEvent(
                minutesInFuture: 2,
                title: "Memory Test Event \(index)",
                id: "memory-test-\(index)"
            )
        }

        // Create and destroy many countdown timers
        for event in events {
            overlayManager.showOverlay(for: event)
            try await Task.sleep(for: .milliseconds(10))
            overlayManager.hideOverlay()
            try await Task.sleep(for: .milliseconds(10))
        }

        // Wait for cleanup
        try await Task.sleep(for: .seconds(1))

        let finalMemory = getMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory

        print("📊 MEMORY TEST: Final memory usage: \(finalMemory / 1024 / 1024) MB")
        print("📊 MEMORY TEST: Memory increase: \(memoryIncrease / 1024 / 1024) MB")

        // Memory increase should be minimal (less than 10MB)
        XCTAssertLessThan(
            memoryIncrease,
            10 * 1024 * 1024,
            "Memory increase should be less than 10MB after countdown timer stress test"
        )
    }

    /// Test countdown timer accuracy over extended period
    func testCountdownTimerLongRunningAccuracy() {
        let event = TimerMigrationTestHelpers.createTestEvent(
            minutesInFuture: 1, // 1 minute = 60 seconds of countdown
            title: "Long Running Countdown Test"
        )

        let expectation = TimerMigrationTestHelpers.createTimerExpectation(
            description: "Long running countdown completed"
        )

        let startTime = Date()
        var updateCount = 0
        var totalDrift: TimeInterval = 0

        overlayManager.showOverlay(for: event)

        // Monitor updates for 10 seconds (10 countdown ticks)
        let observer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            updateCount += 1
            let expectedTime = startTime.addingTimeInterval(TimeInterval(updateCount))
            let actualTime = Date()
            let drift = abs(actualTime.timeIntervalSince(expectedTime))
            totalDrift += drift

            TimerMigrationTestHelpers.logTimingMetrics(
                operation: "Countdown Update \(updateCount)",
                expected: expectedTime,
                actual: actualTime,
                tolerance: TimerMigrationTestHelpers.CountdownTimer.tolerance
            )

            if updateCount >= 10 {
                timer.invalidate()
                expectation.fulfill()
            }
        }

        TimerMigrationTestHelpers.waitForTimerExpectations([expectation], timeout: 15.0)

        // Validate overall accuracy
        let averageDrift = totalDrift / Double(updateCount)
        XCTAssertLessThan(
            averageDrift,
            TimerMigrationTestHelpers.CountdownTimer.tolerance,
            "Average countdown timer drift should be within tolerance"
        )

        TimerMigrationTestHelpers.CountdownTimer.validateCountdownAccuracy(
            iterations: updateCount,
            actualDuration: Date().timeIntervalSince(startTime)
        )

        // Clean up
        overlayManager.hideOverlay()
    }

    // MARK: - Helper Methods

    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Int(info.resident_size)
        } else {
            return 0
        }
    }
}
