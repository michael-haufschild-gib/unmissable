import Foundation
import OSLog
@testable import Unmissable
import XCTest

/// CRITICAL UI INTERACTION DEADLOCK TESTS
/// Tests for dismiss button and snooze functionality deadlocks
@MainActor
class UIInteractionDeadlockTest: XCTestCase {
    private let logger = Logger(subsystem: "com.unmissable.test", category: "UIDeadlockTest")

    func testDismissButtonDeadlock() {
        logger.info("🚨 CRITICAL TEST: Testing dismiss button deadlock scenario")

        // Create test-safe components
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true // Prevent actual UI creation
        )

        let testEvent = TestUtilities.createTestEvent(
            id: "dismiss-deadlock-test",
            title: "Dismiss Deadlock Test",
            startDate: Date().addingTimeInterval(300) // 5 minutes from now
        )

        logger.info("📅 Created test event: \(testEvent.title)")

        // Show overlay first
        logger.info("🎬 Showing overlay...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible after show")

        // Start timing for deadlock detection
        let startTime = Date()
        let maxDismissTime: TimeInterval = 2.0 // Should complete in <2 seconds

        // Test dismiss functionality - this is where deadlock occurs
        logger.info("🔥 TESTING DISMISS: Simulating dismiss button click...")

        var dismissCompleted = false
        var testFailed = false
        var errorMessage = ""

        // Simulate the dismiss button callback directly
        do {
            // This simulates what happens when user clicks dismiss button
            overlayManager.hideOverlay()
            dismissCompleted = true
            logger.info("✅ DISMISS SUCCESS: hideOverlay() completed")

        } catch {
            logger.error("💥 DISMISS EXCEPTION: \(error)")
            testFailed = true
            errorMessage = "Exception during dismiss: \(error.localizedDescription)"
        }

        let totalTime = Date().timeIntervalSince(startTime)
        logger.info("📊 Dismiss test completed in \(totalTime)s")

        // Validate results
        if testFailed {
            logger.error("❌ DISMISS FAILED: \(errorMessage)")
            XCTFail("Dismiss button deadlock detected: \(errorMessage)")
        } else if !dismissCompleted {
            logger.error("❌ DISMISS TIMEOUT: Took longer than \(maxDismissTime)s")
            XCTFail(
                "Dismiss operation took too long (\(totalTime)s > \(maxDismissTime)s), possible deadlock"
            )
        } else {
            logger.info("✅ DISMISS SUCCESS: Completed in \(totalTime)s")
        }

        // Verify final state
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after dismiss")
        XCTAssertLessThan(totalTime, maxDismissTime, "Dismiss should complete quickly")
    }

    func testSnoozeButtonDeadlock() {
        logger.info("🚨 CRITICAL TEST: Testing snooze button deadlock scenario")

        // Create test-safe components
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )

        // Set up EventScheduler connection for snooze functionality
        let eventScheduler = EventScheduler(preferencesManager: preferencesManager)
        overlayManager.setEventScheduler(eventScheduler)

        let testEvent = TestUtilities.createTestEvent(
            id: "snooze-deadlock-test",
            title: "Snooze Deadlock Test",
            startDate: Date().addingTimeInterval(300)
        )

        logger.info("📅 Created test event: \(testEvent.title)")

        // Show overlay first
        logger.info("🎬 Showing overlay...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible after show")

        // Start timing for deadlock detection
        let startTime = Date()
        let maxSnoozeTime: TimeInterval = 2.0 // Should complete in <2 seconds

        // Test snooze functionality - this is where deadlock may occur
        logger.info("⏰ TESTING SNOOZE: Simulating snooze button click for 5 minutes...")

        var snoozeCompleted = false
        var testFailed = false
        var errorMessage = ""

        // Simulate the snooze button callback directly
        do {
            // This simulates what happens when user clicks snooze for 5 minutes
            overlayManager.snoozeOverlay(for: 5)
            snoozeCompleted = true
            logger.info("✅ SNOOZE SUCCESS: snoozeOverlay() completed")

        } catch {
            logger.error("💥 SNOOZE EXCEPTION: \(error)")
            testFailed = true
            errorMessage = "Exception during snooze: \(error.localizedDescription)"
        }

        let totalTime = Date().timeIntervalSince(startTime)
        logger.info("📊 Snooze test completed in \(totalTime)s")

        // Clean up
        overlayManager.hideOverlay()
        eventScheduler.stopScheduling()

        // Validate results
        if testFailed {
            logger.error("❌ SNOOZE FAILED: \(errorMessage)")
            XCTFail("Snooze button deadlock detected: \(errorMessage)")
        } else if !snoozeCompleted {
            logger.error("❌ SNOOZE TIMEOUT: Took longer than \(maxSnoozeTime)s")
            XCTFail(
                "Snooze operation took too long (\(totalTime)s > \(maxSnoozeTime)s), possible deadlock"
            )
        } else {
            logger.info("✅ SNOOZE SUCCESS: Completed in \(totalTime)s")
        }

        XCTAssertLessThan(totalTime, maxSnoozeTime, "Snooze should complete quickly")
    }

    func testJoinButtonDeadlock() throws {
        logger.info("🚨 CRITICAL TEST: Testing join button deadlock scenario")

        // Create test-safe components
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )

        let testEvent = try TestUtilities.createTestEvent(
            id: "join-deadlock-test",
            title: "Join Deadlock Test",
            startDate: Date().addingTimeInterval(300),
            links: [XCTUnwrap(URL(string: "https://meet.google.com/test-meeting"))]
        )

        logger.info("📅 Created test event with meeting link: \(testEvent.title)")

        // Show overlay first
        logger.info("🎬 Showing overlay...")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible after show")

        // Start timing for deadlock detection
        let startTime = Date()
        let maxJoinTime: TimeInterval = 2.0 // Should complete in <2 seconds

        // Test join functionality - simulate join button click
        logger.info("🚀 TESTING JOIN: Simulating join button click...")

        var joinCompleted = false
        var testFailed = false
        var errorMessage = ""

        // Simulate the join button callback directly (without actually opening URL)
        do {
            // This simulates what happens when user clicks join button
            // Note: We can't actually test NSWorkspace.shared.open() in tests, but we can test the hideOverlay part
            overlayManager.hideOverlay() // This is what happens after successful join
            joinCompleted = true
            logger.info("✅ JOIN SUCCESS: join sequence completed")

        } catch {
            logger.error("💥 JOIN EXCEPTION: \(error)")
            testFailed = true
            errorMessage = "Exception during join: \(error.localizedDescription)"
        }

        let totalTime = Date().timeIntervalSince(startTime)
        logger.info("📊 Join test completed in \(totalTime)s")

        // Validate results
        if testFailed {
            logger.error("❌ JOIN FAILED: \(errorMessage)")
            XCTFail("Join button deadlock detected: \(errorMessage)")
        } else if !joinCompleted {
            logger.error("❌ JOIN TIMEOUT: Took longer than \(maxJoinTime)s")
            XCTFail("Join operation took too long (\(totalTime)s > \(maxJoinTime)s), possible deadlock")
        } else {
            logger.info("✅ JOIN SUCCESS: Completed in \(totalTime)s")
        }

        // Verify final state
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after join")
        XCTAssertLessThan(totalTime, maxJoinTime, "Join should complete quickly")
    }

    func testRapidButtonClicking() async throws {
        logger.info("🔄 STRESS TEST: Rapid button clicking to detect deadlocks")

        // Create test-safe components
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )

        let testEvent = TestUtilities.createTestEvent(
            id: "rapid-click-test",
            title: "Rapid Click Test",
            startDate: Date().addingTimeInterval(300)
        )

        // Perform rapid show/dismiss cycles
        for cycle in 1 ... 5 {
            logger.info("🔄 Rapid cycle \(cycle): Show overlay")
            overlayManager.showOverlay(for: testEvent)
            XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible after show")

            logger.info("🔄 Rapid cycle \(cycle): Dismiss overlay")
            overlayManager.hideOverlay()
            XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after dismiss")

            // Small delay to prevent overwhelming the system
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }

        logger.info("✅ Rapid clicking test completed successfully")
    }
}
