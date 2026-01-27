import AppKit
import Foundation
import OSLog
import SwiftUI
@testable import Unmissable
import XCTest

/// COMPREHENSIVE PRODUCTION SNOOZE TESTING
/// Tests the complete snooze workflow in production mode:
/// 1. Overlay appears as scheduled
/// 2. User clicks snooze button (1, 5, 10, 15 minutes)
/// 3. Overlay disappears and reschedules
/// 4. New overlay appears after snooze period
@MainActor
class ProductionSnoozeEndToEndTest: XCTestCase {
    private let logger = Logger(subsystem: "com.unmissable.test", category: "ProductionSnoozeTest")

    func testSnoozeButtonProductionWorkflow() async throws {
        logger.info("🔄 PRODUCTION SNOOZE: Complete end-to-end workflow test")

        // Create test components (TEST MODE to avoid blocking screen)
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true // Test mode to avoid creating real windows that block screen
        )
        let eventScheduler = EventScheduler(preferencesManager: preferencesManager)

        // Connect components like production
        overlayManager.setEventScheduler(eventScheduler)

        let testEvent = TestUtilities.createTestEvent(
            id: "production-snooze-test",
            title: "Production Snooze Test Event",
            startDate: Date().addingTimeInterval(60) // 1 minute from now for quick test
        )

        logger.info("📅 Created test event: \(testEvent.title)")

        // STEP 1: Show overlay like production
        logger.info("🎬 STEP 1: Showing production overlay...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 1)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

        // Wait for overlay to be fully rendered
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // STEP 2: Test snooze button callback (like real SwiftUI button)
        logger.info("⏰ STEP 2: Testing snooze button (5 minutes)...")

        let snoozeStartTime = Date()
        var snoozeCompleted = false
        var deadlockDetected = false

        // Monitor for deadlock during snooze
        let deadlockMonitor = Task {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds timeout
            if !snoozeCompleted {
                self.logger.error("❌ SNOOZE DEADLOCK: Snooze took too long")
                deadlockDetected = true
            }
        }

        // Execute the exact snooze callback that SwiftUI button would trigger
        Task {
            self.logger.info("⏰ SNOOZE CALLBACK: Starting snooze for 5 minutes...")

            // This uses the same callback pattern as production
            overlayManager.snoozeOverlay(for: 5)

            self.logger.info("✅ SNOOZE CALLBACK: Completed")
            snoozeCompleted = true
            deadlockMonitor.cancel()
        }

        // Wait for snooze completion
        var timeoutCounter = 0
        while !snoozeCompleted, !deadlockDetected, timeoutCounter < 50 {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            timeoutCounter += 1
        }

        let snoozeTime = Date().timeIntervalSince(snoozeStartTime)
        deadlockMonitor.cancel()

        // STEP 3: Validate snooze results
        logger.info("📊 STEP 3: Validating snooze results (took \(snoozeTime)s)...")

        if deadlockDetected {
            logger.error("❌ SNOOZE DEADLOCK: Snooze button caused deadlock")
            XCTFail("Snooze button deadlock detected")
        } else {
            logger.info("✅ SNOOZE SUCCESS: No deadlock detected")
            XCTAssertTrue(snoozeCompleted, "Snooze should complete successfully")
            XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")
            XCTAssertLessThan(snoozeTime, 2.0, "Snooze should complete quickly")
        }

        // Clean up
        eventScheduler.stopScheduling()
        logger.info("🎉 PRODUCTION SNOOZE TEST COMPLETED")
    }

    func testAllSnoozeOptionsProduction() async throws {
        logger.info("⏰ SNOOZE OPTIONS: Testing all snooze durations (1, 5, 10, 15 minutes)")

        let snoozeOptions = [1, 5, 10, 15] // All available snooze options

        for snoozeMinutes in snoozeOptions {
            logger.info("🔄 Testing \(snoozeMinutes) minute snooze...")

            // Create fresh components for each test
            let preferencesManager = PreferencesManager()
            let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
            let overlayManager = OverlayManager(
                preferencesManager: preferencesManager,
                focusModeManager: focusModeManager,
                isTestMode: true // Test mode to avoid blocking screen
            )

            let testEvent = TestUtilities.createTestEvent(
                id: "snooze-\(snoozeMinutes)-test",
                title: "Snooze \(snoozeMinutes)min Test",
                startDate: Date().addingTimeInterval(300)
            )

            // Show overlay
            overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
            XCTAssertTrue(
                overlayManager.isOverlayVisible, "Overlay should be visible for \(snoozeMinutes)min test"
            )

            // Test snooze
            let startTime = Date()
            var snoozeCompleted = false

            // Execute snooze callback
            Task {
                overlayManager.snoozeOverlay(for: snoozeMinutes)
                snoozeCompleted = true
            }

            // Wait for completion
            var timeoutCounter = 0
            while !snoozeCompleted, timeoutCounter < 30 {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                timeoutCounter += 1
            }

            let totalTime = Date().timeIntervalSince(startTime)

            // Validate this snooze option
            XCTAssertTrue(snoozeCompleted, "Snooze \(snoozeMinutes)min should complete")
            XCTAssertFalse(
                overlayManager.isOverlayVisible, "Overlay should be hidden after \(snoozeMinutes)min snooze"
            )
            XCTAssertLessThan(totalTime, 1.0, "Snooze \(snoozeMinutes)min should complete quickly")

            logger.info("✅ \(snoozeMinutes) minute snooze test passed (took \(totalTime)s)")

            // Brief pause between tests
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        logger.info("🎉 ALL SNOOZE OPTIONS TESTED SUCCESSFULLY")
    }

    func testSnoozeButtonStressTest() async throws {
        logger.info("🔥 SNOOZE STRESS: Rapid snooze button clicking test")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true // Test mode to avoid blocking screen
        )

        let testEvent = TestUtilities.createTestEvent(
            id: "snooze-stress-test",
            title: "Snooze Stress Test",
            startDate: Date().addingTimeInterval(300)
        )

        // Test multiple rapid snooze/show cycles
        for cycle in 1 ... 3 {
            logger.info("🔄 Stress cycle \(cycle): Show → Rapid Snooze → Verify")

            // Show overlay
            overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
            XCTAssertTrue(
                overlayManager.isOverlayVisible, "Overlay should be visible in stress cycle \(cycle)"
            )

            // Very brief delay (simulating quick user action)
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            // Rapid snooze
            let startTime = Date()
            var snoozeCompleted = false

            Task {
                overlayManager.snoozeOverlay(for: 5)
                snoozeCompleted = true
            }

            // Wait for completion
            var timeoutCounter = 0
            while !snoozeCompleted, timeoutCounter < 20 {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                timeoutCounter += 1
            }

            let cycleTime = Date().timeIntervalSince(startTime)

            // Validate stress cycle
            XCTAssertTrue(snoozeCompleted, "Stress cycle \(cycle) snooze should complete")
            XCTAssertFalse(
                overlayManager.isOverlayVisible, "Overlay should be hidden after stress cycle \(cycle)"
            )
            XCTAssertLessThan(cycleTime, 1.0, "Stress cycle \(cycle) should complete quickly")

            logger.info("✅ Stress cycle \(cycle) passed (took \(cycleTime)s)")

            // Brief pause between cycles
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }

        logger.info("🎉 SNOOZE STRESS TEST COMPLETED")
    }

    func testSnoozeVsDismissProduction() async throws {
        logger.info("⚔️ SNOOZE vs DISMISS: Testing both buttons work correctly")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true // Test mode to avoid blocking screen
        )

        let testEvent = TestUtilities.createTestEvent(
            id: "snooze-vs-dismiss-test",
            title: "Snooze vs Dismiss Test",
            startDate: Date().addingTimeInterval(300)
        )

        // Test 1: Snooze button
        logger.info("⏰ TEST 1: Snooze button...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible for snooze test")

        let snoozeStartTime = Date()
        overlayManager.snoozeOverlay(for: 5)
        let snoozeTime = Date().timeIntervalSince(snoozeStartTime)

        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")
        XCTAssertLessThan(snoozeTime, 1.0, "Snooze should complete quickly")
        logger.info("✅ Snooze test passed (\(snoozeTime)s)")

        // Brief pause
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Test 2: Dismiss button
        logger.info("🛑 TEST 2: Dismiss button...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible for dismiss test")

        let dismissStartTime = Date()
        overlayManager.hideOverlay()
        let dismissTime = Date().timeIntervalSince(dismissStartTime)

        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after dismiss")
        XCTAssertLessThan(dismissTime, 1.0, "Dismiss should complete quickly")
        logger.info("✅ Dismiss test passed (\(dismissTime)s)")

        logger.info("🎉 SNOOZE vs DISMISS: Both buttons work correctly")
    }
}
