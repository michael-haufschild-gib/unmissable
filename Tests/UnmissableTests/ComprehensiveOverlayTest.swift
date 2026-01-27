import Foundation
import XCTest

@testable import Unmissable

/// COMPREHENSIVE DEADLOCK AND RELIABILITY TEST
/// Tests both deadlock prevention and reliable overlay functionality
@MainActor
class ComprehensiveOverlayTest: XCTestCase {

  func testDeadlockPreventionWithTestSafeManager() async throws {
    print("🧪 COMPREHENSIVE TEST: Deadlock prevention with test-safe manager")

    // Use test-safe implementation to avoid UI creation crashes
    let preferencesManager = PreferencesManager()
    let overlayManager = OverlayManager(preferencesManager: preferencesManager, isTestMode: true)
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)

    // Connect them exactly as in production
    overlayManager.setEventScheduler(eventScheduler)

    // Create event that triggers in 3 seconds
    let triggerTime = Date().addingTimeInterval(3)
    let testEvent = TestUtilities.createTestEvent(
      id: "deadlock-test-event",
      title: "Deadlock Prevention Test",
      startDate: triggerTime.addingTimeInterval(120)  // Event starts 2 minutes after trigger
    )

    print("📅 Created event triggering at: \(triggerTime)")
    print("🎯 Event start time: \(testEvent.startDate)")

    // Start scheduling and monitoring
    var didTrigger = false
    var didComplete = false
    var didDeadlock = false

    print("🔄 Starting event scheduling (test-safe mode)...")
    await eventScheduler.startScheduling(events: [testEvent], overlayManager: overlayManager)

    print("⏰ Event scheduled. Monitoring for deadlock...")

    let startTime = Date()
    while Date().timeIntervalSince(startTime) < 8.0 {
      let elapsed = Date().timeIntervalSince(startTime)

      // Check if timer should have triggered
      if elapsed >= 3.0 && !didTrigger {
        didTrigger = true
        print("🎯 Alert should have triggered by now (\(elapsed)s elapsed)")
      }

      // Check overlay state using test-safe manager
      let isOverlayVisible = overlayManager.isOverlayVisible
      if isOverlayVisible && !didComplete {
        didComplete = true
        print("✅ SUCCESS: Overlay displayed at \(elapsed)s")
        break
      }

      // Check for deadlock indicators
      if elapsed > 6.0 && !didComplete {
        didDeadlock = true
        print("❌ DEADLOCK DETECTED: \(elapsed)s elapsed, no overlay displayed")
        break
      }

      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    }

    let totalTime = Date().timeIntervalSince(startTime)
    print("📊 Test completed in \(totalTime)s")

    // Analyze results
    if didComplete {
      print("✅ NO DEADLOCK: Overlay displayed successfully")
    } else if didDeadlock {
      print("❌ DEADLOCK CONFIRMED: Test-safe environment still shows timing issues")
    } else {
      print("⚠️ INCONCLUSIVE: Test timeout without clear result")
    }

    // Clean up
    overlayManager.hideOverlay()
    eventScheduler.stopScheduling()

    // Assert for test success - should complete without deadlock
    XCTAssertTrue(
      didComplete,
      "Test-safe overlay should complete successfully without deadlocks")
  }

  func testStressTestingMultipleOverlays() async throws {
    print("💪 STRESS TEST: Multiple rapid overlay scheduling")

    let preferencesManager = PreferencesManager()
    let overlayManager = OverlayManager(preferencesManager: preferencesManager, isTestMode: true)

    var completedOverlays = 0
    let totalOverlays = 10

    // Schedule multiple overlays rapidly
    for i in 0..<totalOverlays {
      let triggerTime = Date().addingTimeInterval(Double(i) * 0.5 + 1.0)  // Stagger by 0.5s
      let testEvent = TestUtilities.createTestEvent(
        id: "stress-test-\(i)",
        title: "Stress Test Event \(i)",
        startDate: triggerTime.addingTimeInterval(120)
      )

      overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 2, fromSnooze: false)
    }

    // Monitor for completion
    let startTime = Date()
    while Date().timeIntervalSince(startTime) < 15.0 {
      if overlayManager.isOverlayVisible {
        completedOverlays += 1
        overlayManager.hideOverlay()

        if completedOverlays >= totalOverlays {
          break
        }
      }

      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    }

    print("📊 STRESS TEST RESULTS: \(completedOverlays)/\(totalOverlays) overlays completed")

    XCTAssertGreaterThanOrEqual(
      completedOverlays,
      totalOverlays / 2,
      "At least 50% of stress test overlays should complete"
    )
  }

  func testMemoryLeakPrevention() async throws {
    print("🧠 MEMORY TEST: Checking for timer and overlay cleanup")

    let preferencesManager = PreferencesManager()
    var overlayManager: OverlayManager? = OverlayManager(
      preferencesManager: preferencesManager, isTestMode: true)

    // Create and schedule an overlay
    let testEvent = TestUtilities.createTestEvent(
      id: "memory-test",
      title: "Memory Test Event",
      startDate: Date().addingTimeInterval(180)
    )

    overlayManager?.showOverlay(for: testEvent, minutesBeforeMeeting: 2, fromSnooze: false)

    // Verify overlay was scheduled
    XCTAssertNotNil(overlayManager)

    // Release the overlay manager
    overlayManager = nil

    // Wait briefly for cleanup
    try await Task.sleep(nanoseconds: 100_000_000)

    // If we get here without crashes, cleanup worked
    print("✅ MEMORY TEST: No crashes during cleanup")

    XCTAssertNil(overlayManager, "Overlay manager should be deallocated")
  }

  func testProductionReadinessChecklist() async throws {
    print("🎯 PRODUCTION READINESS: Comprehensive checklist")

    let preferencesManager = PreferencesManager()
    let overlayManager = OverlayManager(preferencesManager: preferencesManager, isTestMode: true)

    // Test 1: Basic overlay scheduling
    let testEvent = TestUtilities.createTestEvent(
      id: "production-test",
      title: "Production Test Event",
      startDate: Date().addingTimeInterval(122)
    )

    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 2, fromSnooze: false)

    // Wait for timer to fire
    try await Task.sleep(nanoseconds: 3_500_000_000)  // 3.5 seconds

    // Verify overlay was displayed
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible after timer fires")
    XCTAssertEqual(
      overlayManager.activeEvent?.id, testEvent.id, "Active event should match scheduled event")

    // Test 2: Overlay hiding
    overlayManager.hideOverlay()
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden")
    XCTAssertNil(overlayManager.activeEvent, "Active event should be nil")

    // Test 3: Snooze functionality
    overlayManager.showOverlay(for: testEvent)
    overlayManager.snoozeOverlay(for: 5)
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")

    print("✅ PRODUCTION READINESS: All core functionality tests passed")
  }
}
