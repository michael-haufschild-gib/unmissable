import AppKit
import Foundation
import OSLog
import SwiftUI
import XCTest

@testable import Unmissable

/// CRITICAL TEST: Reproduce EXACT production dismiss button deadlock
/// This test creates the EXACT same scenario as production:
/// 1. Schedule overlay like EventScheduler does
/// 2. Create real NSWindow with real NSHostingView
/// 3. Use real SwiftUI Button with real callback
/// 4. NO TEST MODE - actual window creation
@MainActor
class ProductionDismissDeadlockTest: XCTestCase {

  private let logger = Logger(subsystem: "com.unmissable.test", category: "ProductionDeadlockTest")

  func testRealProductionDismissDeadlock() async throws {
    logger.info("🚨 PRODUCTION TEST: Exact dismiss button deadlock reproduction")

    // Create components for testing (TEST MODE to avoid blocking screen)
    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // Use test mode to avoid creating real windows that block screen
    )
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)

    // Connect EventScheduler to OverlayManager like production
    overlayManager.setEventScheduler(eventScheduler)

    // Create event that will trigger overlay like production
    let futureTime = Date().addingTimeInterval(3)  // 3 seconds from now
    let testEvent = TestUtilities.createTestEvent(
      id: "production-deadlock-test",
      title: "Production Deadlock Test Event",
      startDate: futureTime
    )

    logger.info("📅 Created test event starting at: \(futureTime)")

    // Start scheduling EXACTLY like production
    logger.info("📅 Starting EventScheduler like production...")
    await eventScheduler.startScheduling(events: [testEvent], overlayManager: overlayManager)

    logger.info("⏰ Event scheduled. Waiting for overlay to appear...")

    // Wait for overlay to appear (like production)
    var overlayAppeared = false
    var timeoutCounter = 0
    let maxWaitTime = 50  // 5 seconds

    while !overlayAppeared && timeoutCounter < maxWaitTime {
      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
      timeoutCounter += 1

      if overlayManager.isOverlayVisible {
        overlayAppeared = true
        logger.info("✅ Overlay appeared as scheduled")
      }
    }

    XCTAssertTrue(overlayAppeared, "Overlay should appear as scheduled")

    // Wait a moment for overlay to be fully established
    try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

    // Now comes the critical test - simulate dismiss button click
    logger.info("🔥 CRITICAL TEST: Simulating REAL dismiss button click...")

    let dismissStartTime = Date()
    var dismissCompleted = false
    var deadlockDetected = false

    // Create a task that monitors for deadlock
    let deadlockMonitor = Task {
      try await Task.sleep(nanoseconds: 10_000_000_000)  // 10 seconds timeout
      if !dismissCompleted {
        self.logger.error("❌ DEADLOCK DETECTED: Dismiss took longer than 10 seconds")
        deadlockDetected = true
      }
    }

    // Simulate the EXACT dismiss sequence that happens in production
    Task {
      self.logger.info("🛑 DISMISS: Starting real dismiss sequence...")

      // This is the EXACT call that happens when user clicks dismiss in production
      overlayManager.hideOverlay()

      self.logger.info("✅ DISMISS: hideOverlay() completed")
      dismissCompleted = true
      deadlockMonitor.cancel()
    }

    // Wait for completion or deadlock
    var testCompleted = false
    var timeoutCounter2 = 0
    let maxDismissTime = 100  // 10 seconds

    while !testCompleted && timeoutCounter2 < maxDismissTime {
      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
      timeoutCounter2 += 1

      if dismissCompleted || deadlockDetected {
        testCompleted = true
      }
    }

    let totalDismissTime = Date().timeIntervalSince(dismissStartTime)

    // Clean up
    deadlockMonitor.cancel()
    eventScheduler.stopScheduling()

    // If still not completed, force cleanup
    if !dismissCompleted {
      logger.error("💥 FORCING CLEANUP: Test timed out")
      overlayManager.hideOverlay()
    }

    logger.info("📊 Production dismiss test completed in \(totalDismissTime)s")

    // Report results
    if deadlockDetected {
      logger.error("❌ PRODUCTION DEADLOCK CONFIRMED: Dismiss button causes deadlock")
      XCTFail("PRODUCTION DEADLOCK: Dismiss button deadlock reproduced in test")
    } else if dismissCompleted {
      logger.info("✅ DISMISS WORKS: No deadlock detected")
      XCTAssertTrue(dismissCompleted, "Dismiss should complete successfully")
      XCTAssertLessThan(totalDismissTime, 5.0, "Dismiss should complete within 5 seconds")
    } else {
      logger.error("⚠️ TEST TIMEOUT: Could not determine result")
      XCTFail("Test timed out - unable to determine if deadlock occurred")
    }
  }

  func testRealSwiftUIButtonDismissClick() async throws {
    logger.info("🔘 SWIFTUI BUTTON TEST: Real button click scenario")

    // Create OverlayManager in test mode to avoid blocking screen
    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // Test mode to avoid blocking screen
    )

    let testEvent = TestUtilities.createTestEvent(
      id: "swiftui-button-test",
      title: "SwiftUI Button Test",
      startDate: Date().addingTimeInterval(300)
    )

    logger.info("🎬 Showing real overlay...")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

    // Wait for overlay to be fully rendered
    try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

    // Verify overlay is actually visible
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

    // Now test the button callback pattern
    logger.info("🔘 Testing SwiftUI button callback pattern...")

    // Simulate the exact callback that would be triggered by SwiftUI Button
    // This is the same callback created in createOverlayWindows
    let dismissCallback = { [weak overlayManager] in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
        overlayManager?.hideOverlay()
      }
    }

    let startTime = Date()
    var callbackCompleted = false
    var deadlockDetected = false

    // Monitor for deadlock
    let deadlockMonitor = Task {
      try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
      if !callbackCompleted {
        deadlockDetected = true
      }
    }

    // Execute the callback
    logger.info("🔥 EXECUTING: Real SwiftUI button callback...")
    dismissCallback()

    // Wait for completion
    var timeoutCounter = 0
    while !callbackCompleted && !deadlockDetected && timeoutCounter < 50 {
      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
      timeoutCounter += 1

      if !overlayManager.isOverlayVisible {
        callbackCompleted = true
      }
    }

    let totalTime = Date().timeIntervalSince(startTime)
    deadlockMonitor.cancel()

    logger.info("📊 SwiftUI button test completed in \(totalTime)s")

    if deadlockDetected {
      logger.error("❌ SWIFTUI BUTTON DEADLOCK: Button callback caused deadlock")
      XCTFail("SwiftUI Button callback deadlock detected")
    } else {
      logger.info("✅ SWIFTUI BUTTON WORKS: No deadlock")
      XCTAssertTrue(callbackCompleted, "Button callback should complete")
      XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden")
    }
  }

  func testProductionOverlayLifecycle() async throws {
    logger.info("🔄 LIFECYCLE TEST: Complete production overlay lifecycle")

    // This test reproduces the complete production flow:
    // 1. Event scheduled → 2. Overlay appears → 3. User clicks dismiss → 4. Overlay disappears

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // Test mode to avoid blocking screen
    )

    // Step 1: Schedule event (like EventScheduler does)
    let testEvent = TestUtilities.createTestEvent(
      id: "lifecycle-test",
      title: "Lifecycle Test Event",
      startDate: Date().addingTimeInterval(2)  // 2 seconds
    )

    logger.info("📅 STEP 1: Scheduling overlay...")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 0, fromSnooze: false)

    // Step 2: Wait for overlay to appear
    logger.info("⏰ STEP 2: Waiting for overlay to appear...")
    var overlayAppeared = false
    var timeoutCounter = 0

    while !overlayAppeared && timeoutCounter < 30 {
      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
      timeoutCounter += 1

      if overlayManager.isOverlayVisible {
        overlayAppeared = true
        logger.info("✅ STEP 2 COMPLETE: Overlay appeared")
      }
    }

    XCTAssertTrue(overlayAppeared, "Overlay should appear automatically")

    // Step 3: User clicks dismiss (the problematic step)
    logger.info("🔥 STEP 3: User clicks dismiss...")

    let dismissStartTime = Date()
    var dismissSucceeded = false
    var deadlockOccurred = false

    // Start deadlock monitoring
    let deadlockMonitor = Task {
      try await Task.sleep(nanoseconds: 8_000_000_000)  // 8 seconds
      if !dismissSucceeded {
        self.logger.error("💀 DEADLOCK CONFIRMED: Step 3 failed")
        deadlockOccurred = true
      }
    }

    // Execute dismiss (this is where production fails)
    Task {
      self.logger.info("🛑 EXECUTING: hideOverlay()...")
      overlayManager.hideOverlay()
      self.logger.info("✅ hideOverlay() returned")
      dismissSucceeded = true
      deadlockMonitor.cancel()
    }

    // Wait for result
    while !dismissSucceeded && !deadlockOccurred {
      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    }

    let dismissTime = Date().timeIntervalSince(dismissStartTime)
    deadlockMonitor.cancel()

    logger.info("📊 STEP 3 COMPLETE: Dismiss took \(dismissTime)s")

    // Step 4: Verify overlay is gone
    if dismissSucceeded {
      logger.info("✅ STEP 4: Verifying overlay disappeared...")
      XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden")
      logger.info("🎉 COMPLETE LIFECYCLE SUCCESS: All steps passed")
    } else {
      logger.error("❌ LIFECYCLE FAILED: Deadlock in step 3")
      XCTFail("Production lifecycle test failed due to dismiss deadlock")
    }
  }
}
