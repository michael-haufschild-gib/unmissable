import Foundation
import OSLog
import XCTest

@testable import Unmissable

/// VERIFICATION TEST: Test the async dispatch fix for dismiss deadlock
@MainActor
class AsyncDispatchDeadlockFixTest: XCTestCase {

  private let logger = Logger(subsystem: "com.unmissable.test", category: "AsyncDispatchTest")

  func testAsyncDispatchDeadlockFix() async throws {
    logger.info("🧪 VERIFICATION: Testing async dispatch deadlock fix")

    // Create OverlayManager in test mode to test callback patterns safely
    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // Safe test mode for callback pattern testing
    )

    let testEvent = TestUtilities.createTestEvent(
      id: "async-dispatch-test",
      title: "Async Dispatch Test",
      startDate: Date().addingTimeInterval(300)
    )

    logger.info("📅 Created test event: \(testEvent.title)")

    // Show overlay to establish timer
    logger.info("🎬 Showing overlay...")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

    // Wait for timer to be established
    try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

    // Test the new async callback pattern - simulate dismiss button
    logger.info("🔄 TESTING: New async dispatch pattern for dismiss...")

    let startTime = Date()
    // Use the actual overlay manager to test the dismiss pattern
    // The callback pattern is tested by simply calling hideOverlay and verifying it completes
    let overlay = overlayManager
    
    // Execute dismiss via Task to simulate callback pattern
    Task { @MainActor in
      logger.info("📱 CALLBACK: Starting async dispatch dismiss...")
      overlay.hideOverlay()
      logger.info("✅ ASYNC DISMISS: Completed")
    }

    // Wait for overlay to be hidden
    try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
      return !overlay.isOverlayVisible
    }

    let totalTime = Date().timeIntervalSince(startTime)
    logger.info("📊 Async dispatch test completed in \(totalTime)s")

    // Validate results
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden")
    XCTAssertLessThan(totalTime, 3.0, "Async dismiss should complete quickly")

    logger.info("✅ Async dispatch deadlock fix verification passed")
  }

  func testConcurrentAsyncDispatchCallbacks() async throws {
    logger.info("🔄 STRESS TEST: Concurrent async dispatch callbacks")

    // Create test components
    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )

    let testEvent = TestUtilities.createTestEvent(
      id: "concurrent-async-test",
      title: "Concurrent Async Test",
      startDate: Date().addingTimeInterval(300)
    )

    // Test rapid successive calls (simulating user mashing dismiss button)
    for cycle in 1...5 {
      logger.info("🔄 Cycle \(cycle): Show and rapid async dismiss")

      // Show overlay
      overlayManager.showOverlay(for: testEvent)
      XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible in cycle \(cycle)")

      // Immediate async dismiss (using new pattern)
      var dismissCompleted = false

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
        overlayManager.hideOverlay()
        dismissCompleted = true
      }

      // Wait for completion
      var timeoutCounter = 0
      while !dismissCompleted && timeoutCounter < 20 {  // 2 seconds max
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
        timeoutCounter += 1
      }

      XCTAssertTrue(dismissCompleted, "Cycle \(cycle) should complete")
      XCTAssertFalse(
        overlayManager.isOverlayVisible, "Overlay should be hidden after cycle \(cycle)")

      // Small delay between cycles
      try await Task.sleep(nanoseconds: 50_000_000)  // 0.05 seconds
    }

    logger.info("✅ Concurrent async dispatch stress test completed")
  }

  func testTimerAsyncDispatchInteraction() async throws {
    logger.info("⏰ TIMING TEST: Timer and async dispatch interaction")

    // Create test components
    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )

    let testEvent = TestUtilities.createTestEvent(
      id: "timer-async-test",
      title: "Timer Async Test",
      startDate: Date().addingTimeInterval(5)  // 5 seconds from now (short)
    )

    // Show overlay to start timer
    logger.info("🎬 Showing overlay with active timer...")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 0)  // Immediate alert
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

    // Let timer run for a bit
    logger.info("⏰ Letting timer run...")
    try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

    // Now test dismiss while timer is active
    logger.info("🔥 CRITICAL: Dismiss while timer is active...")

    let startTime = Date()
    var dismissCompleted = false

    // Use the new async pattern
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
      self.logger.info("🛑 ASYNC DISMISS: During active timer...")
      overlayManager.hideOverlay()
      self.logger.info("✅ ASYNC DISMISS: Completed during timer")
      dismissCompleted = true
    }

    // Wait for completion
    var timeoutCounter = 0
    while !dismissCompleted && timeoutCounter < 30 {  // 3 seconds max
      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
      timeoutCounter += 1
    }

    let totalTime = Date().timeIntervalSince(startTime)
    logger.info("📊 Timer-async interaction test completed in \(totalTime)s")

    // Validate results
    XCTAssertTrue(dismissCompleted, "Dismiss should complete even with active timer")
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden")
    XCTAssertLessThan(totalTime, 2.0, "Dismiss should complete quickly even with timer")

    logger.info("✅ Timer-async dispatch interaction test passed")
  }
}
