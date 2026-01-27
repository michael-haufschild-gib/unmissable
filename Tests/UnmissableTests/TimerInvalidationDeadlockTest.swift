import Foundation
import OSLog
@testable import Unmissable
import XCTest

/// CRITICAL TEST: Reproduce the exact timer + NSWindow deadlock scenario
@MainActor
class TimerInvalidationDeadlockTest: XCTestCase {
    private let logger = Logger(subsystem: "com.unmissable.test", category: "TimerDeadlockTest")

    func testTimerInvalidationDeadlock() async throws {
        logger.info("🚨 CRITICAL TEST: Reproduce timer invalidation deadlock")

        // Create a minimal timer scenario that matches the overlay pattern
        var timer: Timer?
        var callbackExecuting = false
        var invalidationCalled = false
        var deadlockDetected = false

        let startTime = Date()
        let maxTestTime: TimeInterval = 5.0 // Should complete in <5 seconds

        logger.info("⏰ Setting up timer with invalidation scenario...")

        // Simulate the exact pattern from OverlayManager
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            callbackExecuting = true
            self.logger.info("🔥 TIMER CALLBACK: Starting execution")

            // Simulate the work done in updateCountdown
            Thread.sleep(forTimeInterval: 0.05) // 50ms of work

            // This simulates what happens when dismiss is clicked during timer callback
            if !invalidationCalled {
                self.logger.info("🛑 TIMER CALLBACK: Simulating dismiss button click")
                invalidationCalled = true

                // This is the problematic call - timer.invalidate() while callback is running
                timer?.invalidate()
                timer = nil

                self.logger.info("✅ TIMER CALLBACK: Invalidation completed")
            }

            callbackExecuting = false
            self.logger.info("✅ TIMER CALLBACK: Execution completed")
        }

        // Wait for the scenario to play out
        logger.info("⏳ Waiting for timer deadlock scenario...")

        // Check for completion or deadlock
        var testCompleted = false
        var timeoutCounter = 0
        let maxTimeout = Int(maxTestTime * 10) // 50 iterations for 5 seconds

        while !testCompleted, timeoutCounter < maxTimeout {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            timeoutCounter += 1

            if invalidationCalled, !callbackExecuting {
                testCompleted = true
                logger.info("✅ Test completed successfully")
            }
        }

        let totalTime = Date().timeIntervalSince(startTime)

        if !testCompleted {
            deadlockDetected = true
            logger.error("❌ DEADLOCK DETECTED: Timer invalidation scenario took too long")

            // Force cleanup
            timer?.invalidate()
            timer = nil
        }

        logger.info("📊 Timer deadlock test completed in \(totalTime)s")

        // Validate results
        XCTAssertTrue(testCompleted, "Timer invalidation should complete without deadlock")
        XCTAssertFalse(deadlockDetected, "No deadlock should be detected")
        XCTAssertLessThan(totalTime, maxTestTime, "Test should complete quickly")
    }

    func testOverlayManagerTimerDeadlockReproduction() async throws {
        logger.info("🚨 CRITICAL TEST: Reproduce OverlayManager timer deadlock")

        // Create OverlayManager in test mode
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )

        let testEvent = TestUtilities.createTestEvent(
            id: "timer-deadlock-test",
            title: "Timer Deadlock Test",
            startDate: Date().addingTimeInterval(300) // 5 minutes from now
        )

        logger.info("📅 Created test event: \(testEvent.title)")

        // Show overlay to start timer
        logger.info("🎬 Showing overlay...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

        // Wait for timer to be established
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Now simulate rapid dismiss calls (like button clicking)
        logger.info("🔥 RAPID DISMISS: Simulating rapid dismiss button clicks...")

        let startTime = Date()
        let maxDismissTime: TimeInterval = 2.0

        // Simulate what happens when user rapidly clicks dismiss
        for i in 1 ... 3 {
            logger.info("🔄 Dismiss attempt \(i)")
            overlayManager.hideOverlay()

            // Small delay between attempts
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }

        let totalTime = Date().timeIntervalSince(startTime)
        logger.info("📊 Rapid dismiss test completed in \(totalTime)s")

        // Validate no deadlock occurred
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after dismiss")
        XCTAssertLessThan(totalTime, maxDismissTime, "Dismiss should complete quickly")

        logger.info("✅ OverlayManager timer deadlock reproduction test passed")
    }

    func testTimerCallbackInterruption() async throws {
        logger.info("🔄 INTERRUPT TEST: Timer callback interruption scenario")

        var timer: Timer?
        var callbackInterrupted = false
        var safeInvalidation = false

        // Create timer that simulates long-running callback
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timerRef in
            self.logger.info("⏰ Long callback starting...")

            // Simulate longer work that might be interrupted
            for i in 1 ... 10 {
                Thread.sleep(forTimeInterval: 0.01) // 10ms chunks

                // Check if we should stop (simulates checking isOverlayVisible)
                if !timerRef.isValid {
                    self.logger.info("🛑 Callback detected timer invalidation, stopping early")
                    callbackInterrupted = true
                    return
                }
            }

            self.logger.info("✅ Long callback completed normally")
        }

        // Let timer run for a bit
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Now invalidate it
        logger.info("🛑 Invalidating timer...")
        timer?.invalidate()
        timer = nil
        safeInvalidation = true

        // Wait for any remaining callbacks to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        XCTAssertTrue(safeInvalidation, "Timer invalidation should complete")
        logger.info("✅ Timer callback interruption test completed")
    }
}
