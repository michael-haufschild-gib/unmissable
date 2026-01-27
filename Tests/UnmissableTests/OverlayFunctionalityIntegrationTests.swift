import Foundation
import OSLog
import XCTest

@testable import Unmissable

/// COMPREHENSIVE OVERLAY FUNCTIONALITY INTEGRATION TESTS
/// This test consolidates all overlay-related functionality tests
/// Focus: Complete overlay lifecycle and integration testing
@MainActor
class OverlayFunctionalityIntegrationTests: XCTestCase {

  private let logger = Logger(subsystem: "com.unmissable.test", category: "OverlayFunctionality")

  // MARK: - Test Environment Setup

  override func setUp() async throws {
    try await super.setUp()
    logger.info("🧪 Setting up Overlay Functionality Integration Test Suite")
  }

  override func tearDown() async throws {
    logger.info("🧹 Cleaning up Overlay Functionality Integration Test Suite")
    try await super.tearDown()
  }

  // MARK: - CORE: Overlay Lifecycle Management

  func testOverlayLifecycleComplete() async throws {
    logger.info("🔄 CORE: Complete overlay lifecycle test")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )

    let testEvent = TestUtilities.createTestEvent(
      id: "lifecycle-test",
      title: "Overlay Lifecycle Test",
      startDate: Date().addingTimeInterval(300),
      links: [URL(string: "https://meet.google.com/test-room")!]
    )

    // Initial state
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should start hidden")
    XCTAssertNil(overlayManager.activeEvent, "No active event initially")

    // Show overlay
    logger.info("📊 Phase 1: Show overlay")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)

    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible after show")
    XCTAssertEqual(overlayManager.activeEvent?.id, testEvent.id, "Active event should match")

    // Wait for timer establishment
    try await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

    // Test overlay state during active timer
    logger.info("📊 Phase 2: Overlay with active timer")
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should remain visible")

    // Hide overlay
    logger.info("📊 Phase 3: Hide overlay")
    overlayManager.hideOverlay()

    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after hide")
    XCTAssertNil(overlayManager.activeEvent, "No active event after hide")

    logger.info("✅ Complete overlay lifecycle test passed")
  }

  // MARK: - CORE: Overlay Timing and Scheduling

  func testOverlayTimingAndScheduling() async throws {
    logger.info("⏰ CORE: Overlay timing and scheduling test")

    let preferencesManager = PreferencesManager()
    // Use immediate timing for tests
    preferencesManager.overlayShowMinutesBefore = 0
    
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)
    overlayManager.setEventScheduler(eventScheduler)

    // Test 1: Future event scheduling (1 hour from now)
    logger.info("📊 Test 1: Future event scheduling")
    let futureEvent = TestUtilities.createTestEvent(
      id: "future-timing-test",
      title: "Future Event",
      startDate: Date().addingTimeInterval(3600)
    )

    // Reset timing to 5 mins for this test
    preferencesManager.overlayShowMinutesBefore = 5
    
    await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

    // Should not trigger immediately (even with scheduler loop)
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertFalse(overlayManager.isOverlayVisible, "Future event should not trigger immediately")
    
    eventScheduler.stopScheduling()
    overlayManager.hideOverlay()

    // Test 2: Immediate event scheduling (imminent event)
    logger.info("📊 Test 2: Immediate event scheduling (imminent)")
    let imminentEvent = TestUtilities.createTestEvent(
      id: "immediate-timing-test",
      title: "Imminent Event",
      startDate: Date().addingTimeInterval(5),  // 5 seconds from now
      endDate: Date().addingTimeInterval(3605)
    )

    await eventScheduler.startScheduling(events: [imminentEvent], overlayManager: overlayManager)

    // Should trigger immediately because overlay window (start-5min) has passed
    // but meeting hasn't started yet (start > now)
    try await Task.sleep(nanoseconds: 200_000_000)
    
    XCTAssertTrue(overlayManager.isOverlayVisible, "Imminent event should trigger immediately")
    
    eventScheduler.stopScheduling()
    overlayManager.hideOverlay()

    // Test 3: Near-future event scheduling
    logger.info("📊 Test 3: Near-future event scheduling")
    let nearEvent = TestUtilities.createTestEvent(
      id: "near-timing-test",
      title: "Near Future Event",
      startDate: Date().addingTimeInterval(60)  // 1 minute from now
    )
    
    // Set preference to 2 minutes before
    preferencesManager.overlayShowMinutesBefore = 2

    await eventScheduler.startScheduling(events: [nearEvent], overlayManager: overlayManager)

    // Since 1 min < 2 min, it should trigger immediately (missed/imminent)
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Near-future event inside window should trigger immediately")

    overlayManager.hideOverlay()
    eventScheduler.stopScheduling()
    logger.info("✅ Overlay timing and scheduling test passed")
  }

  // MARK: - CORE: Snooze Functionality Complete

  func testSnoozeLifecycleComplete() async throws {
    logger.info("💤 CORE: Complete snooze lifecycle test")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)
    overlayManager.setEventScheduler(eventScheduler)

    let testEvent = TestUtilities.createTestEvent(
      id: "snooze-lifecycle-test",
      title: "Snooze Lifecycle Test",
      startDate: Date().addingTimeInterval(300)
    )

    // Phase 1: Initial overlay
    logger.info("📊 Phase 1: Show initial overlay")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Initial overlay should be visible")

    // Phase 2: Snooze for different durations
    for minutes in [1, 5, 10, 15] {
      logger.info("📊 Phase 2.\(minutes): Snooze for \(minutes) minutes")

      overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
      XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible before snooze")

      let snoozeStart = Date()
      overlayManager.snoozeOverlay(for: minutes)
      let snoozeTime = Date().timeIntervalSince(snoozeStart)

      XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")
      XCTAssertLessThan(snoozeTime, 1.0, "Snooze operation should be fast")
    }

    // Phase 3: Snoozed overlay display
    logger.info("📊 Phase 3: Show snoozed overlay")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 0, fromSnooze: true)

    XCTAssertTrue(overlayManager.isOverlayVisible, "Snoozed overlay should be visible")
    XCTAssertEqual(overlayManager.activeEvent?.id, testEvent.id, "Active event should match")

    // Phase 4: Snoozed overlay behavior
    logger.info("📊 Phase 4: Snoozed overlay behavior")

    // Snoozed overlays should behave differently (longer auto-hide threshold)
    // Test that we can dismiss snoozed overlay normally
    overlayManager.hideOverlay()
    XCTAssertFalse(overlayManager.isOverlayVisible, "Snoozed overlay should be dismissible")

    logger.info("✅ Complete snooze lifecycle test passed")
  }

  // MARK: - INTEGRATION: EventScheduler + OverlayManager

  func testEventSchedulerIntegration() async throws {
    logger.info("🔗 INTEGRATION: EventScheduler + OverlayManager test")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)
    overlayManager.setEventScheduler(eventScheduler)

    let events = [
      TestUtilities.createTestEvent(
        id: "integration-event-1",
        title: "Integration Test Event 1",
        startDate: Date().addingTimeInterval(180)  // 3 minutes
      ),
      TestUtilities.createTestEvent(
        id: "integration-event-2",
        title: "Integration Test Event 2",
        startDate: Date().addingTimeInterval(600)  // 10 minutes
      ),
    ]

    // Test 1: Start scheduling
    logger.info("📊 Test 1: Start event scheduling")
    let schedulingStart = Date()
    await eventScheduler.startScheduling(events: events, overlayManager: overlayManager)
    let schedulingTime = Date().timeIntervalSince(schedulingStart)

    XCTAssertLessThan(schedulingTime, 2.0, "Event scheduling should complete quickly")

    // Test 2: Manual overlay trigger through scheduler
    logger.info("📊 Test 2: Manual overlay trigger")
    overlayManager.showOverlay(for: events[0], minutesBeforeMeeting: 5, fromSnooze: false)

    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    XCTAssertTrue(overlayManager.isOverlayVisible, "Scheduled overlay should be visible")

    // Test 3: Snooze through scheduler
    logger.info("📊 Test 3: Snooze through scheduler")
    eventScheduler.scheduleSnooze(for: events[0], minutes: 2)

    // Note: scheduleSnooze just schedules future snooze, doesn't hide current overlay
    // Key test: no crash or deadlock occurred during snooze scheduling

    // Test 4: Stop scheduling
    logger.info("📊 Test 4: Stop scheduling")
    let stopStart = Date()
    eventScheduler.stopScheduling()
    let stopTime = Date().timeIntervalSince(stopStart)

    XCTAssertLessThan(stopTime, 1.0, "Stop scheduling should complete quickly")

    logger.info("✅ EventScheduler integration test passed")
  }

  // MARK: - INTEGRATION: Focus Mode Integration

  func testFocusModeIntegration() async throws {
    logger.info("🔕 INTEGRATION: Focus mode integration test")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )

    let testEvent = TestUtilities.createTestEvent(
      id: "focus-mode-test",
      title: "Focus Mode Test",
      startDate: Date().addingTimeInterval(300)
    )

    // Test 1: Normal mode (focus mode disabled)
    logger.info("📊 Test 1: Normal mode overlay")
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should show in normal mode")
    overlayManager.hideOverlay()

    // Test 2: Focus mode effects (implementation-dependent)
    logger.info("📊 Test 2: Focus mode behavior")

    // The actual focus mode behavior depends on system state
    // Key test: overlay manager handles focus mode without crashing
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)

    // Whether overlay shows depends on focusModeManager.shouldShowOverlay()
    // The important thing is no crash occurred

    overlayManager.hideOverlay()

    logger.info("✅ Focus mode integration test passed")
  }

  // MARK: - INTEGRATION: Preferences Integration

  func testPreferencesIntegration() async throws {
    logger.info("⚙️ INTEGRATION: Preferences integration test")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)

    // Test different preference configurations
    let testConfigs = [
      ("minimal-mode", { preferencesManager.minimalMode = true }),
      ("large-font", { preferencesManager.fontSize = .large }),
      ("dark-theme", { preferencesManager.appearanceTheme = .dark }),
      ("high-opacity", { preferencesManager.overlayOpacity = 0.9 }),
    ]

    for (configName, configSetup) in testConfigs {
      logger.info("📊 Testing configuration: \(configName)")

      configSetup()

      let overlayManager = OverlayManager(
        preferencesManager: preferencesManager,
        focusModeManager: focusModeManager,
        isTestMode: true
      )

      let testEvent = TestUtilities.createTestEvent(
        id: "preferences-test-\(configName)",
        title: "Preferences Test \(configName)",
        startDate: Date().addingTimeInterval(300)
      )

      // Test overlay with different preferences
      overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
      XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should show with \(configName)")

      overlayManager.hideOverlay()
      XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should hide with \(configName)")
    }

    logger.info("✅ Preferences integration test passed")
  }

  // MARK: - ACCURACY: Event Display and Content

  func testEventDisplayAccuracy() async throws {
    logger.info("🎯 ACCURACY: Event display accuracy test")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )

    // Create comprehensive test event
    let complexEvent = Event(
      id: "accuracy-test",
      title: "Complex Meeting with All Features",
      startDate: Date().addingTimeInterval(300),
      endDate: Date().addingTimeInterval(3900),
      organizer: "test@example.com",
      description: "This is a detailed meeting description with HTML formatting",
      location: "Conference Room A / Google Meet",
      attendees: [
        Attendee(
          name: "John Doe", email: "john@example.com", status: .accepted, isOrganizer: true,
          isSelf: false),
        Attendee(name: "Jane Smith", email: "jane@example.com", status: .tentative, isSelf: false),
        Attendee(email: "user@example.com", status: .accepted, isSelf: true),
      ],
      calendarId: "primary",
      links: [URL(string: "https://meet.google.com/test-room")!],
      provider: .meet
    )

    // Test overlay with complex event
    logger.info("📊 Testing overlay with complex event data")
    overlayManager.showOverlay(for: complexEvent, minutesBeforeMeeting: 5)

    XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should show complex event")
    XCTAssertEqual(overlayManager.activeEvent?.id, complexEvent.id, "Active event should match")
    XCTAssertEqual(
      overlayManager.activeEvent?.title, complexEvent.title, "Event title should match")
    XCTAssertEqual(
      overlayManager.activeEvent?.organizer, complexEvent.organizer, "Organizer should match")
    XCTAssertEqual(
      overlayManager.activeEvent?.attendees.count, complexEvent.attendees.count,
      "Attendee count should match")
    XCTAssertEqual(
      overlayManager.activeEvent?.provider, complexEvent.provider, "Provider should match")

    overlayManager.hideOverlay()

    // Test different event types
    let eventTypes = [
      TestUtilities.createTestEvent(
        title: "No Link Event", startDate: Date().addingTimeInterval(300)),
      TestUtilities.createMeetingEvent(provider: .zoom, startDate: Date().addingTimeInterval(300)),
      TestUtilities.createMeetingEvent(provider: .teams, startDate: Date().addingTimeInterval(300)),
      TestUtilities.createMeetingEvent(provider: .webex, startDate: Date().addingTimeInterval(300)),
    ]

    for event in eventTypes {
      logger.info("📊 Testing event type: \(event.provider?.displayName ?? "No Provider")")

      overlayManager.showOverlay(for: event, minutesBeforeMeeting: 5)
      XCTAssertTrue(
        overlayManager.isOverlayVisible,
        "Overlay should show for \(event.provider?.displayName ?? "basic") event")
      XCTAssertEqual(overlayManager.activeEvent?.id, event.id, "Active event ID should match")

      overlayManager.hideOverlay()
    }

    logger.info("✅ Event display accuracy test passed")
  }

  // MARK: - COMPREHENSIVE: All Features Combined

  func testAllOverlayFeaturesComprehensive() async throws {
    logger.info("🚀 COMPREHENSIVE: All overlay features combined test")

    let preferencesManager = PreferencesManager()
    let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
    let overlayManager = OverlayManager(
      preferencesManager: preferencesManager,
      focusModeManager: focusModeManager,
      isTestMode: true
    )
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)
    overlayManager.setEventScheduler(eventScheduler)

    let testEvent = TestUtilities.createMeetingEvent(
      provider: .meet,
      startDate: Date().addingTimeInterval(300)
    )

    let startTime = Date()

    // 1. Start with event scheduling
    await eventScheduler.startScheduling(events: [testEvent], overlayManager: overlayManager)

    // 2. Show initial overlay
    overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Initial overlay should be visible")

    // 3. Let timer run
    try await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

    // 4. Test snooze
    overlayManager.snoozeOverlay(for: 1)
    XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")

    // 5. Show snoozed overlay
    overlayManager.showOverlay(for: testEvent, fromSnooze: true)
    XCTAssertTrue(overlayManager.isOverlayVisible, "Snoozed overlay should be visible")

    // 6. Test rapid operations
    for _ in 1...3 {
      overlayManager.hideOverlay()
      overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
    }

    // 7. Final cleanup
    overlayManager.hideOverlay()
    eventScheduler.stopScheduling()

    XCTAssertFalse(overlayManager.isOverlayVisible, "Final state should be hidden")

    let totalTime = Date().timeIntervalSince(startTime)
    XCTAssertLessThan(totalTime, 5.0, "Comprehensive test should complete quickly")

    logger.info("✅ All overlay features comprehensive test completed in \(totalTime)s")
  }
}
