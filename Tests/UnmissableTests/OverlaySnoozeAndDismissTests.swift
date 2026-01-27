import Combine
import XCTest

@testable import Unmissable

/// Comprehensive tests for overlay snooze and dismiss functionality
@MainActor
final class OverlaySnoozeAndDismissTests: XCTestCase {

  var overlayManager: OverlayManager!
  var mockPreferences: PreferencesManager!
  var focusModeManager: FocusModeManager!
  var eventScheduler: EventScheduler!
  var cancellables: Set<AnyCancellable>!

  override func setUp() async throws {
    mockPreferences = TestUtilities.createTestPreferencesManager()
    focusModeManager = FocusModeManager(preferencesManager: mockPreferences)
    overlayManager = OverlayManager(
      preferencesManager: mockPreferences, focusModeManager: focusModeManager, isTestMode: true)
    eventScheduler = EventScheduler(preferencesManager: mockPreferences)
    overlayManager.setEventScheduler(eventScheduler)
    cancellables = Set<AnyCancellable>()

    try await super.setUp()
  }

  override func tearDown() async throws {
    overlayManager.hideOverlay()
    cancellables.removeAll()

    overlayManager = nil
    eventScheduler = nil
    focusModeManager = nil
    mockPreferences = nil

    try await super.tearDown()
  }

  // MARK: - Snooze Functionality Tests

  func testSnoozeOverlayHidesOverlay() async throws {
    // Test that snooze properly hides the overlay
    let event = TestUtilities.createTestEvent()

    overlayManager.showOverlay(for: event)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible initially")
    XCTAssertNotNil(overlayManager.activeEvent, "Should have active event")

    // Snooze for 5 minutes
    overlayManager.snoozeOverlay(for: 5)

    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")
    XCTAssertNil(overlayManager.activeEvent, "Active event should be cleared after snooze")
  }

  func testSnoozeOverlaySchedulesCorrectSnoozeAlert() async throws {
    // Test that snooze schedules a new alert with correct timing
    let event = TestUtilities.createTestEvent(
      title: "Important Meeting",
      startDate: Date().addingTimeInterval(600)  // 10 minutes from now
    )

    overlayManager.showOverlay(for: event)

    // Snooze for 3 minutes
    let snoozeMinutes = 3
    overlayManager.snoozeOverlay(for: snoozeMinutes)

    // Verify snooze was scheduled correctly
    XCTAssertTrue(eventScheduler.snoozeScheduled, "Snooze should be scheduled")
    XCTAssertEqual(
      eventScheduler.snoozeMinutes, snoozeMinutes, "Should schedule correct snooze duration")
    XCTAssertEqual(
      eventScheduler.snoozeEvent?.id, event.id, "Should schedule snooze for correct event")

    // Verify timing is approximately correct (within 5 seconds tolerance)
    let expectedSnoozeTime = Date().addingTimeInterval(TimeInterval(snoozeMinutes * 60))
    let actualSnoozeTime = eventScheduler.snoozeTime!
    let timeDifference = abs(expectedSnoozeTime.timeIntervalSince(actualSnoozeTime))

    XCTAssertLessThan(timeDifference, 5.0, "Snooze time should be approximately correct")
  }

  func testSnoozeWithDifferentDurations() async throws {
    // Test snooze with various durations (1, 5, 10, 15 minutes)
    let testDurations = [1, 5, 10, 15]

    for duration in testDurations {
      eventScheduler.reset()

      let event = TestUtilities.createTestEvent(title: "Test Meeting \(duration)")
      overlayManager.showOverlay(for: event)

      overlayManager.snoozeOverlay(for: duration)

      XCTAssertTrue(
        eventScheduler.snoozeScheduled, "Snooze should be scheduled for \(duration) minutes")
      XCTAssertEqual(
        eventScheduler.snoozeMinutes, duration,
        "Should schedule correct duration: \(duration) minutes")
      XCTAssertFalse(
        overlayManager.isOverlayVisible, "Overlay should be hidden after \(duration)-minute snooze")
    }
  }

  func testSnoozeOverlayStopsCountdownTimer() async throws {
    // Test that snoozing stops the countdown timer
    let event = TestUtilities.createTestEvent()

    overlayManager.showOverlay(for: event)

    // Let timer run briefly
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    let initialCountdown = overlayManager.timeUntilMeeting

    // Snooze the overlay
    overlayManager.snoozeOverlay(for: 5)
    let countdownAfterSnooze = overlayManager.timeUntilMeeting

    // Wait and verify timer stopped
    try await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds
    let countdownAfterWait = overlayManager.timeUntilMeeting

    XCTAssertEqual(countdownAfterSnooze, countdownAfterWait, "Timer should stop after snooze")
  }

  // MARK: - Dismiss Functionality Tests

  func testDismissOverlayHidesOverlay() async throws {
    // Test that dismiss properly hides the overlay
    let event = TestUtilities.createTestEvent()

    overlayManager.showOverlay(for: event)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible initially")
    XCTAssertNotNil(overlayManager.activeEvent, "Should have active event")

    overlayManager.hideOverlay()

    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after dismiss")
    XCTAssertNil(overlayManager.activeEvent, "Active event should be cleared after dismiss")
  }

  func testDismissOverlayStopsCountdownTimer() async throws {
    // Test that dismissing stops the countdown timer
    let event = TestUtilities.createTestEvent()

    overlayManager.showOverlay(for: event)

    // Let timer run briefly
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    let initialCountdown = overlayManager.timeUntilMeeting

    // Dismiss the overlay
    overlayManager.hideOverlay()
    let countdownAfterDismiss = overlayManager.timeUntilMeeting

    // Wait and verify timer stopped
    try await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds
    let countdownAfterWait = overlayManager.timeUntilMeeting

    XCTAssertEqual(countdownAfterDismiss, countdownAfterWait, "Timer should stop after dismiss")
  }

  func testDismissDoesNotScheduleSnooze() async throws {
    // Test that dismiss doesn't accidentally schedule a snooze
    let event = TestUtilities.createTestEvent()

    overlayManager.showOverlay(for: event)
    overlayManager.hideOverlay()

    XCTAssertFalse(eventScheduler.snoozeScheduled, "Dismiss should not schedule snooze")
    XCTAssertNil(eventScheduler.snoozeEvent, "No snooze event should be set")
  }

  // MARK: - Rapid Interaction Tests

  func testRapidSnoozeAndDismissInteractions() async throws {
    // Test rapid snooze/dismiss interactions don't cause issues
    let event = TestUtilities.createTestEvent()

    for i in 0..<5 {
      eventScheduler.reset()

      overlayManager.showOverlay(for: event)
      XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should show for iteration \(i)")

      if i % 2 == 0 {
        // Even iterations: snooze
        overlayManager.snoozeOverlay(for: 1)
        XCTAssertTrue(eventScheduler.snoozeScheduled, "Snooze should work on iteration \(i)")
      } else {
        // Odd iterations: dismiss
        overlayManager.hideOverlay()
        XCTAssertFalse(eventScheduler.snoozeScheduled, "Dismiss should work on iteration \(i)")
      }

      XCTAssertFalse(
        overlayManager.isOverlayVisible, "Overlay should be hidden after iteration \(i)")
    }
  }

  func testSnoozeWhileOverlayNotVisible() async throws {
    // Test that snooze calls when overlay is not visible don't cause issues
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should not be visible initially")

    // This should not crash or cause issues
    overlayManager.snoozeOverlay(for: 5)

    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should still not be visible")
    XCTAssertFalse(
      eventScheduler.snoozeScheduled, "No snooze should be scheduled when no overlay is active")
  }

  // MARK: - Error Handling Tests

  func testSnoozeWithInvalidDuration() async throws {
    // Test snooze with edge case durations
    let event = TestUtilities.createTestEvent()

    // Test zero duration
    overlayManager.showOverlay(for: event)
    overlayManager.snoozeOverlay(for: 0)

    XCTAssertFalse(
      overlayManager.isOverlayVisible, "Overlay should be hidden even with 0-minute snooze")

    // Test very large duration
    eventScheduler.reset()
    overlayManager.showOverlay(for: event)
    overlayManager.snoozeOverlay(for: 1440)  // 24 hours

    XCTAssertTrue(eventScheduler.snoozeScheduled, "Large snooze duration should still work")
    XCTAssertEqual(eventScheduler.snoozeMinutes, 1440, "Should handle large durations")
  }

  // MARK: - State Consistency Tests

  func testOverlayStateConsistencyAfterSnooze() async throws {
    // Test that all overlay state is properly reset after snooze
    let event = TestUtilities.createTestEvent()

    overlayManager.showOverlay(for: event)

    // Capture initial state
    XCTAssertTrue(overlayManager.isOverlayVisible)
    XCTAssertNotNil(overlayManager.activeEvent)
    XCTAssertGreaterThan(overlayManager.timeUntilMeeting, 0)  // Timer should be running

    overlayManager.snoozeOverlay(for: 5)

    // Verify all state is properly reset
    XCTAssertFalse(overlayManager.isOverlayVisible, "isOverlayVisible should be false")
    XCTAssertNil(overlayManager.activeEvent, "activeEvent should be nil")

    // timeUntilMeeting state after snooze can vary, but timer should be stopped
    try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
    let countdownAfterWait = overlayManager.timeUntilMeeting

    try await Task.sleep(nanoseconds: 1_000_000_000)  // Another 1 second
    let countdownAfterSecondWait = overlayManager.timeUntilMeeting

    XCTAssertEqual(
      countdownAfterWait, countdownAfterSecondWait, "Timer should not be running after snooze")
  }

  func testOverlayStateConsistencyAfterDismiss() async throws {
    // Test that all overlay state is properly reset after dismiss
    let event = TestUtilities.createTestEvent()

    overlayManager.showOverlay(for: event)

    // Capture initial state
    XCTAssertTrue(overlayManager.isOverlayVisible)
    XCTAssertNotNil(overlayManager.activeEvent)

    overlayManager.hideOverlay()

    // Verify all state is properly reset
    XCTAssertFalse(overlayManager.isOverlayVisible, "isOverlayVisible should be false")
    XCTAssertNil(overlayManager.activeEvent, "activeEvent should be nil")

    // Timer should be stopped
    try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
    let countdownAfterWait = overlayManager.timeUntilMeeting

    try await Task.sleep(nanoseconds: 1_000_000_000)  // Another 1 second
    let countdownAfterSecondWait = overlayManager.timeUntilMeeting

    XCTAssertEqual(
      countdownAfterWait, countdownAfterSecondWait, "Timer should not be running after dismiss")
  }
}
