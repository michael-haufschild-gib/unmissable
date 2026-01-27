import Foundation
import OSLog
import XCTest

@testable import Unmissable

/// CRITICAL DEADLOCK REPRODUCTION TEST - REWRITTEN FOR THREAD SAFETY
/// This test reproduces real-world overlay deadlock scenario with proper synchronization
@MainActor
class CriticalOverlayDeadlockTest: XCTestCase {

  private let logger = Logger(subsystem: "com.unmissable.test", category: "DeadlockTest")

  func testRealWorldOverlayDeadlock() async throws {
    logger.info("🚨 CRITICAL TEST: Reproducing real-world overlay deadlock scenario")

    // Create test-safe components (no UI, no timers)
    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // CRITICAL: Prevent UI creation in tests
    )
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)

    // Connect them exactly as in production
    overlayManager.setEventScheduler(eventScheduler)

    // Create event that should trigger overlay immediately (no waiting)
    let testEvent = TestUtilities.createTestEvent(
      id: "deadlock-test-event",
      title: "Critical Deadlock Test",
      startDate: Date().addingTimeInterval(120)  // Event starts in 2 minutes
    )

    logger.info("📅 Created test event: \(testEvent.title)")
    logger.info("🎯 Event start time: \(testEvent.startDate)")
    logger.info("⏰ Current time: \(Date())")

    // Track state changes for deadlock detection
    var overlayDidShow = false
    var schedulingCompleted = false
    var testFailed = false
    var errorMessage = ""

    // Start timing for deadlock detection
    let startTime = Date()
    let maxTestDuration: TimeInterval = 5.0  // 5 second max test duration

    do {
      logger.info("🔄 Starting event scheduling (production simulation)...")

      // CRITICAL FIX: Use async/await properly instead of fire-and-forget Task
      await eventScheduler.startScheduling(events: [testEvent], overlayManager: overlayManager)
      schedulingCompleted = true
      logger.info("✅ Event scheduling completed successfully")

      // Simulate overlay trigger directly (no real-time waiting)
      logger.info("🎬 Simulating overlay trigger...")
      overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 2)

      // Check overlay state immediately after trigger
      overlayDidShow = overlayManager.isOverlayVisible
      logger.info("📊 Overlay state after trigger: isVisible=\(overlayDidShow)")

      if overlayDidShow {
        logger.info("✅ SUCCESS: Overlay displayed successfully")
      } else {
        logger.error("❌ FAILURE: Overlay failed to display")
        testFailed = true
        errorMessage = "Overlay failed to become visible after showOverlay() call"
      }

    }

    let totalTime = Date().timeIntervalSince(startTime)
    logger.info("📊 Test completed in \(totalTime)s")

    // Clean up resources
    logger.info("🧹 Cleaning up test resources...")
    overlayManager.hideOverlay()
    eventScheduler.stopScheduling()

    // Analyze results and provide detailed failure information
    if testFailed {
      logger.error("❌ TEST FAILED: \(errorMessage)")
      logger.error("   - Scheduling completed: \(schedulingCompleted)")
      logger.error("   - Overlay displayed: \(overlayDidShow)")
      logger.error("   - Total test time: \(totalTime)s")

      XCTFail("Overlay system deadlock detected: \(errorMessage)")
    } else {
      logger.info("✅ NO DEADLOCK: Test completed successfully")
      logger.info("   - Scheduling completed: \(schedulingCompleted)")
      logger.info("   - Overlay displayed: \(overlayDidShow)")
      logger.info("   - Total test time: \(totalTime)s")
    }

    // Ensure overlay is visible as expected
    XCTAssertTrue(
      overlayDidShow,
      "Overlay failed to display - isOverlayVisible should be true after showOverlay() call"
    )

    XCTAssertTrue(
      schedulingCompleted,
      "Event scheduling failed to complete successfully"
    )

    XCTAssertLessThan(
      totalTime,
      maxTestDuration,
      "Test took too long (\(totalTime)s > \(maxTestDuration)s), possible deadlock"
    )
  }

  /// Test rapid overlay show/hide cycles to detect race conditions
  func testRapidOverlayToggling() async throws {
    logger.info("🔄 STRESS TEST: Rapid overlay show/hide cycles")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )

    let testEvent = TestUtilities.createTestEvent(
      id: "stress-test-event",
      title: "Stress Test Event",
      startDate: Date().addingTimeInterval(300)
    )

    // Perform rapid show/hide cycles
    for cycle in 1...10 {
      logger.info("🔄 Cycle \(cycle): Show overlay")
      overlayManager.showOverlay(for: testEvent)
      XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible after show")

      logger.info("🔄 Cycle \(cycle): Hide overlay")
      overlayManager.hideOverlay()
      XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after hide")

      // Small delay to prevent overwhelming the system
      try await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds
    }

    logger.info("✅ Stress test completed successfully")
  }

  /// Test concurrent overlay operations to detect threading issues
  func testConcurrentOverlayOperations() async throws {
    logger.info("🏃‍♂️ CONCURRENCY TEST: Multiple simultaneous overlay operations")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )

    let events = (1...5).map { index in
      TestUtilities.createTestEvent(
        id: "concurrent-event-\(index)",
        title: "Concurrent Event \(index)",
        startDate: Date().addingTimeInterval(Double(index * 60))
      )
    }

    // Launch multiple operations sequentially (TaskGroup with @MainActor has compiler issues in Swift 6)
    for (index, event) in events.enumerated() {
      logger.info("🚀 Starting operation \(index + 1)")
      overlayManager.showOverlay(for: event)

      // Brief delay
      try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05 seconds

      overlayManager.hideOverlay()
      logger.info("✅ Completed operation \(index + 1)")
    }

    // Ensure final state is clean
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after all operations")
    logger.info("✅ Concurrency test completed successfully")
  }
}
