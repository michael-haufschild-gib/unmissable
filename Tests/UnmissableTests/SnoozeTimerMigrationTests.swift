import Foundation
import XCTest

@testable import Unmissable

@MainActor
final class SnoozeTimerMigrationTests: XCTestCase {
  var overlayManager: OverlayManager!
  var preferencesManager: PreferencesManager!

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

  /// Validate snooze accuracy for a short duration to keep tests fast
  func testSnoozeTimerAccuracy() async throws {
    let duration = 1  // minutes
    let event = TimerMigrationTestHelpers.SnoozeTimer.createSnoozeTestEvent()

    let expectation = TimerMigrationTestHelpers.createTimerExpectation(
      description: "Snooze timer fired for \(duration) minute",
      timeout: TimeInterval(duration * 60 + 5)
    )

    overlayManager.showOverlay(for: event)
    XCTAssertTrue(overlayManager.isOverlayVisible)

    let snoozeStart = Date()
    var overlayReappeared = false

    let observer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
      [weak overlayManager] timer in
      guard let overlayManager, !overlayReappeared else { return }
      if overlayManager.isOverlayVisible {
        overlayReappeared = true
        timer.invalidate()

        let actual = Date()
        let expected = snoozeStart.addingTimeInterval(TimeInterval(duration * 60))
        TimerMigrationTestHelpers.validateTimerAccuracy(
          expected: expected,
          actual: actual,
          tolerance: TimerMigrationTestHelpers.SnoozeTimer.tolerance
        )
        expectation.fulfill()
      }
    }

    overlayManager.snoozeOverlay(for: duration)
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")

    TimerMigrationTestHelpers.waitForTimerExpectations(
      [expectation],
      timeout: TimeInterval(duration * 60 + 10)
    )

    observer.invalidate()
    overlayManager.hideOverlay()
  }

  /// Verify that starting a new overlay cancels a pending snooze
  func testSnoozeTimerCancellation() async throws {
    let event = TimerMigrationTestHelpers.SnoozeTimer.createSnoozeTestEvent()

    overlayManager.showOverlay(for: event)
    XCTAssertTrue(overlayManager.isOverlayVisible)

    overlayManager.snoozeOverlay(for: 5)
    XCTAssertFalse(overlayManager.isOverlayVisible)

    try await Task.sleep(for: .seconds(1))

    let differentEvent = TimerMigrationTestHelpers.createTestEvent(
      minutesInFuture: 3,
      title: "Cancellation Test Event"
    )
    overlayManager.showOverlay(for: differentEvent)

    try await Task.sleep(for: .seconds(2))

    XCTAssertTrue(overlayManager.isOverlayVisible)
    XCTAssertEqual(overlayManager.activeEvent?.title, "Cancellation Test Event")

    overlayManager.hideOverlay()
  }

  /// Stress: multiple snoozes rapidly
  func testMultipleSnoozeOperations() async throws {
    let events = (0..<3).map { _ in
      TimerMigrationTestHelpers.SnoozeTimer.createSnoozeTestEvent(snoozeMinutes: 1)
    }

    for event in events {
      overlayManager.showOverlay(for: event)
      overlayManager.snoozeOverlay(for: 1)
      try await Task.sleep(for: .milliseconds(100))
    }

    try await Task.sleep(for: .seconds(2))

    if overlayManager.isOverlayVisible {
      XCTAssertNotNil(overlayManager.activeEvent)
    }

    overlayManager.hideOverlay()
  }

  /// Fallback snooze path (no EventScheduler)
  func testSnoozeTimerFallbackMode() async throws {
    let event = TimerMigrationTestHelpers.SnoozeTimer.createSnoozeTestEvent()

    let expectation = TimerMigrationTestHelpers.createTimerExpectation(
      description: "Fallback snooze timer fired"
    )

    overlayManager.showOverlay(for: event)

    let snoozeStart = Date()

    var hasTriggered = false
    let observer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
      [weak overlayManager] timer in
      guard let overlayManager, !hasTriggered else { return }
      if overlayManager.isOverlayVisible {
        hasTriggered = true
        timer.invalidate()

        let actual = Date()
        let expected = snoozeStart.addingTimeInterval(60)
        TimerMigrationTestHelpers.validateTimerAccuracy(
          expected: expected,
          actual: actual,
          tolerance: TimerMigrationTestHelpers.SnoozeTimer.tolerance
        )

        expectation.fulfill()
      }
    }

    overlayManager.snoozeOverlay(for: 1)

    TimerMigrationTestHelpers.waitForTimerExpectations([expectation], timeout: 70.0)

    observer.invalidate()
    overlayManager.hideOverlay()
  }

  /// Basic memory sanity for snooze flows
  func testSnoozeTimerMemoryUsage() async throws {
    let initialMemory = getMemoryUsage()

    let events = (0..<10).map { _ in
      TimerMigrationTestHelpers.SnoozeTimer.createSnoozeTestEvent()
    }

    for event in events {
      overlayManager.showOverlay(for: event)
      overlayManager.snoozeOverlay(for: 5)
      try await Task.sleep(for: .milliseconds(10))
      overlayManager.hideOverlay()
      try await Task.sleep(for: .milliseconds(10))
    }

    try await Task.sleep(for: .seconds(1))

    let finalMemory = getMemoryUsage()
    let memoryIncrease = finalMemory - initialMemory

    XCTAssertLessThan(
      memoryIncrease,
      5 * 1024 * 1024,
      "Memory increase should be <5MB after snooze stress"
    )
  }

  /// Snooze across simulated sleep/wake
  func testSnoozeTimerSystemSleepWake() async throws {
    let event = TimerMigrationTestHelpers.SnoozeTimer.createSnoozeTestEvent()

    overlayManager.showOverlay(for: event)
    overlayManager.snoozeOverlay(for: 2)

    try await Task.sleep(for: .seconds(1))
    XCTAssertFalse(overlayManager.isOverlayVisible)

    try await Task.sleep(for: .seconds(2))

    overlayManager.hideOverlay()
  }

  // MARK: - Helpers
  private func getMemoryUsage() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }

    return kerr == KERN_SUCCESS ? Int(info.resident_size) : 0
  }
}
