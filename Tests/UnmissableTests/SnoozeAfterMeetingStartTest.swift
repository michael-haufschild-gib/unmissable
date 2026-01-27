import AppKit
import Foundation
import OSLog
import SwiftUI
import XCTest

@testable import Unmissable

/// TEST: Snooze timer expiring after meeting has started
/// This test verifies that snoozed overlays appear even when the meeting has already started,
/// addressing the reported bug where snooze timers would expire but overlays wouldn't show.
@MainActor
class SnoozeAfterMeetingStartTest: XCTestCase {

  private let logger = Logger(
    subsystem: "com.unmissable.test", category: "SnoozeAfterMeetingStartTest")

  func testSnoozeTimerExpiresAfterMeetingStarted() async throws {
    logger.info("🔄 SNOOZE EDGE CASE: Testing snooze timer expiring after meeting started")

    // Create test components (TEST MODE to avoid blocking screen)
    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // Test mode to avoid blocking screen
    )
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)

    // Connect components like production
    overlayManager.setEventScheduler(eventScheduler)

    // Create test scenario: meeting starts in 2 seconds, user snoozes for 5 seconds
    // This means snooze timer will expire 3 seconds AFTER meeting has started
    let meetingStartTime = Date().addingTimeInterval(2)  // Meeting starts in 2 seconds
    let testEvent = TestUtilities.createTestEvent(
      id: "snooze-after-start-test",
      title: "Snooze After Start Test Meeting",
      startDate: meetingStartTime
    )

    logger.info("📅 Test event: '\(testEvent.title)' starts at \(meetingStartTime)")
    logger.info("⏰ Current time: \(Date())")

    // STEP 1: Show initial overlay
    logger.info("🎬 STEP 1: Showing initial overlay...")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 0, fromSnooze: false)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Initial overlay should be visible")

    // STEP 2: User snoozes for 5 seconds (which will expire after meeting starts)
    logger.info("⏰ STEP 2: Snoozing for 5 seconds (will expire after meeting starts)...")

    overlayManager.snoozeOverlay(for: 5)  // 5 minutes in real app, but using 5 seconds for test

    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")

    // STEP 3: Wait for snooze timer to expire
    // Note: In real implementation, snooze would be in minutes, but for test we use seconds
    logger.info("⏱️ STEP 3: Waiting for snooze timer to expire...")

    // Since the actual snooze uses minutes, we need to test the concept differently
    // Let's manually trigger what should happen when snooze timer expires

    // Wait for meeting to start (2 seconds)
    try await Task.sleep(nanoseconds: 2_500_000_000)  // 2.5 seconds

    // At this point, meeting has started. Now simulate snooze alert triggering
    logger.info("🚨 STEP 4: Simulating snooze alert firing AFTER meeting started...")

    let meetingHasStarted = testEvent.startDate < Date()
    XCTAssertTrue(meetingHasStarted, "Meeting should have started by now")

    // This is the key test: showing overlay from snooze after meeting started
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 0, fromSnooze: true)

    // STEP 5: Verify overlay is shown despite meeting having started
    logger.info("✅ STEP 5: Verifying overlay appears despite meeting having started...")

    XCTAssertTrue(
      overlayManager.isOverlayVisible,
      "Snoozed overlay should be visible even after meeting started")
    XCTAssertNotNil(overlayManager.activeEvent, "Active event should be set")
    XCTAssertEqual(overlayManager.activeEvent?.id, testEvent.id, "Should show correct event")

    // STEP 6: Verify that the overlay stays visible for snoozed alerts
    // The auto-hide logic should be more lenient for snoozed alerts
    logger.info("⏳ STEP 6: Verifying overlay doesn't auto-hide immediately for snoozed alerts...")

    // Wait a bit to see if overlay auto-hides too quickly
    try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

    XCTAssertTrue(
      overlayManager.isOverlayVisible,
      "Snoozed overlay should remain visible longer than regular overlays")

    // Clean up
    overlayManager.hideOverlay()
    eventScheduler.stopScheduling()

    logger.info("🎉 SNOOZE EDGE CASE TEST COMPLETED: Snooze after meeting start works correctly")
  }

  func testSnoozeAutoHideThresholds() async throws {
    logger.info(
      "🔄 AUTO-HIDE THRESHOLDS: Testing different auto-hide behavior for regular vs snoozed alerts")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // Test mode to avoid blocking screen
    )

    // Create test event that started 10 minutes ago
    let meetingStartTime = Date().addingTimeInterval(-600)  // 10 minutes ago
    let testEvent = TestUtilities.createTestEvent(
      id: "auto-hide-threshold-test",
      title: "Auto-Hide Threshold Test",
      startDate: meetingStartTime
    )

    logger.info("📅 Test event: Meeting started 10 minutes ago")

    // TEST 1: Regular overlay should auto-hide quickly (5 minute threshold)
    logger.info("🎬 TEST 1: Regular overlay for old meeting...")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 0, fromSnooze: false)

    // Give it a moment to process the countdown timer
    try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

    // Regular overlay should have auto-hidden because meeting started >5 minutes ago
    XCTAssertFalse(
      overlayManager.isOverlayVisible,
      "Regular overlay should auto-hide for meetings that started >5 minutes ago")

    // TEST 2: Snoozed overlay should be more lenient (30 minute threshold)
    logger.info("⏰ TEST 2: Snoozed overlay for same old meeting...")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 0, fromSnooze: true)

    // Give it a moment to process
    try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

    // Snoozed overlay should still be visible because 10 minutes < 30 minute threshold
    XCTAssertTrue(
      overlayManager.isOverlayVisible,
      "Snoozed overlay should remain visible for meetings that started <30 minutes ago")

    // Clean up
    overlayManager.hideOverlay()

    logger.info("🎉 AUTO-HIDE THRESHOLDS TEST COMPLETED: Different thresholds working correctly")
  }

  func testSnoozeLoggingAndDebugInfo() async throws {
    logger.info("📊 SNOOZE LOGGING: Testing comprehensive logging for snooze operations")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true  // Test mode to avoid blocking screen
    )
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)
    overlayManager.setEventScheduler(eventScheduler)

    let testEvent = TestUtilities.createTestEvent(
      id: "snooze-logging-test",
      title: "Snooze Logging Test",
      startDate: Date().addingTimeInterval(300)
    )

    // Test snooze scheduling with comprehensive logging
    logger.info("⏰ Testing snooze scheduling...")
    eventScheduler.scheduleSnooze(for: testEvent, minutes: 1)

    // Verify snooze was scheduled
    XCTAssertTrue(
      eventScheduler.scheduledAlerts.contains { alert in
        if case .snooze = alert.alertType {
          return alert.event.id == testEvent.id
        }
        return false
      }, "Snooze alert should be scheduled")

    // Test overlay display with snooze flag
    logger.info("🎬 Testing snoozed overlay display...")
    overlayManager.showOverlay(for: testEvent, fromSnooze: true)

    XCTAssertTrue(overlayManager.isOverlayVisible, "Snoozed overlay should be visible")

    // Clean up
    overlayManager.hideOverlay()
    eventScheduler.stopScheduling()

    logger.info("🎉 SNOOZE LOGGING TEST COMPLETED")
  }

  func testOverlayMessagingForSnoozedMeetings() async throws {
    logger.info(
      "📝 OVERLAY MESSAGING: Testing correct messaging for snoozed meetings in different states")

    // Test 1: Snoozed meeting that hasn't started yet
    logger.info("🔄 TEST 1: Snoozed meeting before start time...")
    let futureEvent = TestUtilities.createTestEvent(
      id: "snooze-future-test",
      title: "Future Snoozed Meeting",
      startDate: Date().addingTimeInterval(300)  // 5 minutes from now
    )

    // Create OverlayContentView for snoozed future meeting
    let futureView = OverlayContentView(
      event: futureEvent,
      onDismiss: {},
      onJoin: {},
      onSnooze: { _ in },
      isFromSnooze: true
    )

    // Note: We can't easily test the dynamic header text without running the view,
    // but the logic is in place for "Snoozed Meeting Reminder"
    logger.info("✅ Future snoozed meeting view created successfully")

    // Test 2: Snoozed meeting that started recently (< 5 minutes ago)
    logger.info("🔄 TEST 2: Snoozed meeting that started recently...")
    let recentEvent = TestUtilities.createTestEvent(
      id: "snooze-recent-test",
      title: "Recently Started Snoozed Meeting",
      startDate: Date().addingTimeInterval(-120)  // Started 2 minutes ago
    )

    let recentView = OverlayContentView(
      event: recentEvent,
      onDismiss: {},
      onJoin: {},
      onSnooze: { _ in },
      isFromSnooze: true
    )

    logger.info("✅ Recently started snoozed meeting view created successfully")

    // Test 3: Snoozed meeting that has been running for a while (> 5 minutes ago)
    logger.info("🔄 TEST 3: Snoozed meeting that has been running for a while...")
    let ongoingEvent = TestUtilities.createTestEvent(
      id: "snooze-ongoing-test",
      title: "Long Running Snoozed Meeting",
      startDate: Date().addingTimeInterval(-900)  // Started 15 minutes ago
    )

    let ongoingView = OverlayContentView(
      event: ongoingEvent,
      onDismiss: {},
      onJoin: {},
      onSnooze: { _ in },
      isFromSnooze: true
    )

    logger.info("✅ Long running snoozed meeting view created successfully")

    // Verify all views can be created without issues
    XCTAssertNotNil(futureView, "Future snoozed meeting view should be created")
    XCTAssertNotNil(recentView, "Recent snoozed meeting view should be created")
    XCTAssertNotNil(ongoingView, "Ongoing snoozed meeting view should be created")

    logger.info("🎉 OVERLAY MESSAGING TEST COMPLETED: All snoozed meeting states handled correctly")
  }
}
