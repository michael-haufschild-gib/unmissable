import Foundation
import OSLog
import XCTest

@testable import Unmissable

/// VALIDATION TEST: Confirm dismiss button deadlock is fixed
@MainActor
class DismissDeadlockFixValidationTest: XCTestCase {

  private let logger = Logger(subsystem: "com.unmissable.test", category: "DismissFixValidation")

  func testDismissButtonWorksWithoutDeadlock() async throws {
    logger.info("✅ VALIDATION: Testing dismiss button fix")

    // Create test-mode OverlayManager to avoid blocking screen
    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // Test mode to avoid blocking screen
    )

    let testEvent = TestUtilities.createTestEvent(
      id: "dismiss-fix-validation",
      title: "Dismiss Fix Validation",
      startDate: Date().addingTimeInterval(300)
    )

    // Show overlay
    logger.info("🎬 Showing overlay...")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

    // Wait for overlay to be established
    try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

    // Test dismiss - this should NOT deadlock anymore
    logger.info("🔥 CRITICAL: Testing dismiss (should not deadlock)...")

    let startTime = Date()
    overlayManager.hideOverlay()
    let dismissTime = Date().timeIntervalSince(startTime)

    logger.info("✅ DISMISS COMPLETED in \(dismissTime)s")

    // Validate results
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden")
    XCTAssertLessThan(dismissTime, 1.0, "Dismiss should complete quickly")

    logger.info("🎉 DISMISS DEADLOCK FIX VALIDATED: Test passed!")
  }

  func testMultipleRapidDismissCalls() async throws {
    logger.info("🔄 STRESS TEST: Multiple rapid dismiss calls")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // Test mode to avoid blocking screen
    )

    let testEvent = TestUtilities.createTestEvent(
      id: "rapid-dismiss-test",
      title: "Rapid Dismiss Test",
      startDate: Date().addingTimeInterval(300)
    )

    // Test multiple show/dismiss cycles
    for cycle in 1...3 {
      logger.info("🔄 Cycle \(cycle): Show and rapid dismiss")

      // Show overlay
      overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
      XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible in cycle \(cycle)")

      // Small delay
      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

      // Rapid dismiss
      let startTime = Date()
      overlayManager.hideOverlay()
      let dismissTime = Date().timeIntervalSince(startTime)

      logger.info("✅ Cycle \(cycle) dismiss completed in \(dismissTime)s")

      XCTAssertFalse(
        overlayManager.isOverlayVisible, "Overlay should be hidden after cycle \(cycle)")
      XCTAssertLessThan(dismissTime, 0.5, "Dismiss should be fast in cycle \(cycle)")

      // Brief pause between cycles
      try await Task.sleep(nanoseconds: 50_000_000)  // 0.05 seconds
    }

    logger.info("🎉 RAPID DISMISS STRESS TEST PASSED")
  }
}
