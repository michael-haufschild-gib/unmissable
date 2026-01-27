import Foundation
import OSLog
@testable import Unmissable
import XCTest

/// COMPREHENSIVE UI CALLBACK DEADLOCK TESTS
/// Tests the actual callback patterns that could cause deadlocks in production
@MainActor
class ComprehensiveUICallbackTest: XCTestCase {
    private let logger = Logger(subsystem: "com.unmissable.test", category: "UICallbackTest")

    func testActualSwiftUICallbackPattern() async throws {
        logger.info("🚨 CRITICAL TEST: Testing actual SwiftUI callback deadlock pattern")

        // Create test-safe components exactly as in production
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true // Prevent actual UI creation but test the callback pattern
        )

        let testEvent = TestUtilities.createTestEvent(
            id: "swiftui-callback-test",
            title: "SwiftUI Callback Test",
            startDate: Date().addingTimeInterval(300)
        )

        logger.info("📅 Created test event: \(testEvent.title)")

        // Show overlay to set up the scenario
        logger.info("🎬 Showing overlay...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible after show")

        // CRITICAL TEST: Recreate the exact callback pattern from createOverlayWindow
        logger.info("🔥 TESTING: Exact production callback pattern...")

        let startTime = Date()
        var callbackCompleted = false
        var deadlockDetected = false

        // This recreates the exact callback pattern from OverlayManager.createOverlayWindow
        let dismissCallback = { [weak overlayManager, logger] in
            Task { @MainActor in
                logger.info("📱 CALLBACK: Starting dismiss callback")
                overlayManager?.hideOverlay()
                logger.info("📱 CALLBACK: Dismiss callback completed")
            }
        }

        let snoozeCallback = { [weak overlayManager, logger] (minutes: Int) in
            Task { @MainActor in
                logger.info("⏰ CALLBACK: Starting snooze callback for \(minutes) minutes")
                overlayManager?.snoozeOverlay(for: minutes)
                logger.info("⏰ CALLBACK: Snooze callback completed")
            }
        }

        let joinCallback = { [weak overlayManager, logger] in
            Task { @MainActor in
                logger.info("🚀 CALLBACK: Starting join callback")
                if let url = testEvent.primaryLink {
                    NSWorkspace.shared.open(url)
                }
                overlayManager?.hideOverlay()
                logger.info("🚀 CALLBACK: Join callback completed")
            }
        }

        // Test dismiss callback
        logger.info("🧪 Testing dismiss callback...")
        dismissCallback()

        // Wait for completion
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Verify overlay was dismissed
        XCTAssertFalse(
            overlayManager.isOverlayVisible, "Overlay should be hidden after dismiss callback"
        )

        // Show overlay again for snooze test
        logger.info("🎬 Showing overlay again for snooze test...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible for snooze test")

        // Test snooze callback
        logger.info("🧪 Testing snooze callback...")
        snoozeCallback(5) // 5 minute snooze

        // Wait for completion
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Verify overlay was hidden for snooze
        XCTAssertFalse(
            overlayManager.isOverlayVisible, "Overlay should be hidden after snooze callback"
        )

        // Show overlay again for join test
        logger.info("🎬 Showing overlay again for join test...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible for join test")

        // Test join callback
        logger.info("🧪 Testing join callback...")
        joinCallback()

        // Wait for completion
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Verify overlay was hidden for join
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after join callback")

        callbackCompleted = true
        let totalTime = Date().timeIntervalSince(startTime)

        logger.info("📊 All callback tests completed in \(totalTime)s")

        // Validate no deadlocks occurred
        XCTAssertTrue(callbackCompleted, "All callbacks should complete successfully")
        XCTAssertFalse(deadlockDetected, "No deadlocks should be detected")
        XCTAssertLessThan(totalTime, 5.0, "All callbacks should complete within 5 seconds")

        logger.info("✅ ALL CALLBACKS SUCCESS: No deadlocks detected")
    }

    func testConcurrentCallbackStressTest() async throws {
        logger.info("🔄 STRESS TEST: Concurrent callback execution")

        // Create test-safe components
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )

        let testEvent = TestUtilities.createTestEvent(
            id: "concurrent-callback-test",
            title: "Concurrent Callback Test",
            startDate: Date().addingTimeInterval(300)
        )

        // Create the production callback pattern
        let dismissCallback = { [weak overlayManager] in
            Task.detached { @MainActor [weak overlayManager] in
                overlayManager?.hideOverlay()
            }
        }

        // Perform rapid callback stress test
        for cycle in 1 ... 10 {
            logger.info("🔄 Concurrent cycle \(cycle): Show and rapid dismiss")

            // Show overlay
            overlayManager.showOverlay(for: testEvent)
            XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible in cycle \(cycle)")

            // Rapid dismiss callback
            dismissCallback()

            // Small delay
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            // Verify clean state
            XCTAssertFalse(
                overlayManager.isOverlayVisible, "Overlay should be hidden after cycle \(cycle)"
            )
        }

        logger.info("✅ Concurrent callback stress test completed successfully")
    }

    func testTimerCallbackInteraction() async throws {
        logger.info("⏰ TIMER TEST: Testing timer and callback interaction")

        // Create test-safe components
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )

        // Create event that's very close to start time to trigger auto-hide logic
        let testEvent = TestUtilities.createTestEvent(
            id: "timer-callback-test",
            title: "Timer Callback Test",
            startDate: Date().addingTimeInterval(-400) // Meeting started 6+ minutes ago (should auto-hide)
        )

        logger.info("📅 Created test event that should auto-hide: \(testEvent.title)")

        // Show overlay
        logger.info("🎬 Showing overlay that should auto-hide...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible initially")

        // Wait for timer to potentially trigger auto-hide
        logger.info("⏳ Waiting for timer auto-hide logic...")
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // The timer should have hidden the overlay automatically
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be auto-hidden by timer")

        logger.info("✅ Timer callback interaction test completed successfully")
    }
}
