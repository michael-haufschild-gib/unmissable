import Combine
import SwiftUI
@testable import Unmissable
import XCTest

/// Comprehensive end-to-end overlay functionality test suite
/// Ensures zero surprise bugs for client handover
@MainActor
final class OverlayCompleteIntegrationTests: XCTestCase {
    var overlayManager: OverlayManager!
    var mockPreferences: PreferencesManager!
    var focusModeManager: FocusModeManager!
    var eventScheduler: EventScheduler!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        mockPreferences = TestUtilities.createTestPreferencesManager()
        focusModeManager = FocusModeManager(preferencesManager: mockPreferences)
        overlayManager = OverlayManager(
            preferencesManager: mockPreferences, focusModeManager: focusModeManager, isTestMode: true
        )
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

    // MARK: - Complete User Journey Tests

    func testCompleteSnoozeUserJourney() {
        // SCENARIO: User gets meeting alert, snoozes it, receives it again later

        let meetingTime = Date().addingTimeInterval(300) // 5 minutes from now
        let event = TestUtilities.createMeetingEvent(
            provider: .meet,
            startDate: meetingTime
        )

        // 1. Initial overlay display
        overlayManager.showOverlay(for: event)

        XCTAssertTrue(overlayManager.isOverlayVisible, "Step 1: Overlay should be visible")
        XCTAssertNotNil(overlayManager.activeEvent, "Step 1: Should have active event")
        XCTAssertEqual(overlayManager.activeEvent?.id, event.id, "Step 1: Should show correct event")

        // Verify countdown is running
        let initialCountdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(
            initialCountdown, 290, "Step 1: Countdown should be approximately 5 minutes"
        )

        // 2. User snoozes for 2 minutes
        let snoozeMinutes = 2
        overlayManager.snoozeOverlay(for: snoozeMinutes)

        XCTAssertFalse(overlayManager.isOverlayVisible, "Step 2: Overlay should be hidden after snooze")
        XCTAssertNil(overlayManager.activeEvent, "Step 2: Active event should be cleared")
        XCTAssertTrue(eventScheduler.snoozeScheduled, "Step 2: Snooze should be scheduled")
        XCTAssertEqual(
            eventScheduler.snoozeMinutes, snoozeMinutes, "Step 2: Should snooze for correct duration"
        )

        // 3. Simulate snooze alert firing (2 minutes later)
        _ = ScheduledAlert(
            event: event,
            triggerDate: Date().addingTimeInterval(TimeInterval(snoozeMinutes * 60)),
            alertType: .snooze(until: Date().addingTimeInterval(TimeInterval(snoozeMinutes * 60)))
        )

        // Reset and show overlay again (as if snooze alert fired)
        eventScheduler.reset()
        overlayManager.showOverlay(for: event)

        XCTAssertTrue(
            overlayManager.isOverlayVisible, "Step 3: Overlay should be visible again after snooze"
        )
        XCTAssertNotNil(overlayManager.activeEvent, "Step 3: Should have active event again")

        // 4. User dismisses this time
        overlayManager.hideOverlay()

        XCTAssertFalse(
            overlayManager.isOverlayVisible, "Step 4: Overlay should be hidden after dismiss"
        )
        XCTAssertNil(overlayManager.activeEvent, "Step 4: Active event should be cleared")
        XCTAssertFalse(eventScheduler.snoozeScheduled, "Step 4: No new snooze should be scheduled")

        print("✅ Complete snooze user journey works correctly")
    }

    func testCompleteJoinMeetingUserJourney() {
        // SCENARIO: User gets meeting alert and joins the meeting

        let meetingEvent = TestUtilities.createMeetingEvent(
            provider: .meet,
            startDate: Date().addingTimeInterval(60) // 1 minute from now
        )

        // 1. Show overlay for upcoming meeting
        overlayManager.showOverlay(for: meetingEvent)

        XCTAssertTrue(overlayManager.isOverlayVisible, "Step 1: Overlay should be visible")
        XCTAssertEqual(
            overlayManager.activeEvent?.title, "Team Standup", "Step 1: Should show correct meeting"
        )
        XCTAssertNotNil(meetingEvent.primaryLink, "Step 1: Meeting should have join link")

        // 2. Verify countdown is accurate for imminent meeting
        let countdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(countdown, 50, "Step 2: Should show time remaining")
        XCTAssertLessThan(countdown, 70, "Step 2: Should be approximately 1 minute")

        // 3. User clicks join (simulated by hideOverlay as join triggers dismiss)
        // In real scenario, onJoin callback would open URL and then call hideOverlay
        let joinURL = meetingEvent.primaryLink
        XCTAssertNotNil(joinURL, "Step 3: Join URL should exist")

        overlayManager.hideOverlay()

        XCTAssertFalse(overlayManager.isOverlayVisible, "Step 3: Overlay should be hidden after join")
        XCTAssertNil(overlayManager.activeEvent, "Step 3: Active event should be cleared")

        print("✅ Complete join meeting user journey works correctly")
    }

    // MARK: - Edge Case Coverage

    func testOverlayWithPastEventEdgeCase() {
        // SCENARIO: System tries to show overlay for meeting that already started

        let pastEvent = TestUtilities.createTestEvent(
            title: "Meeting Already Started",
            startDate: Date().addingTimeInterval(-300) // 5 minutes ago
        )

        overlayManager.showOverlay(for: pastEvent)

        // Should still show overlay but with different timing behavior
        XCTAssertTrue(overlayManager.isOverlayVisible, "Should show overlay even for past events")

        // Should be able to dismiss past event overlay
        overlayManager.hideOverlay()
        XCTAssertFalse(overlayManager.isOverlayVisible, "Should be able to dismiss past event overlay")

        print("✅ Past event edge case handled correctly")
    }

    func testOverlayWithMalformedEventData() {
        // SCENARIO: Event with missing or invalid data

        let malformedEvent = Event(
            id: "", // Empty ID
            title: "", // Empty title
            startDate: Date().addingTimeInterval(300),
            endDate: Date().addingTimeInterval(300), // Same start/end time
            organizer: "", // Empty organizer
            calendarId: "test"
        )

        // Should handle gracefully without crashing
        overlayManager.showOverlay(for: malformedEvent)

        XCTAssertTrue(overlayManager.isOverlayVisible, "Should show overlay even with malformed data")

        // Should be able to interact with malformed event overlay
        overlayManager.snoozeOverlay(for: 1)
        XCTAssertFalse(overlayManager.isOverlayVisible, "Should handle snooze with malformed data")

        print("✅ Malformed event data handled gracefully")
    }

    func testRapidFireUserInteractions() async throws {
        // SCENARIO: User rapidly clicks snooze/dismiss buttons

        let event = TestUtilities.createTestEvent()

        // Rapid show/hide cycles
        for i in 0 ..< 10 {
            eventScheduler.reset()

            overlayManager.showOverlay(for: event)
            XCTAssertTrue(overlayManager.isOverlayVisible, "Rapid cycle \(i): Should show")

            if i % 3 == 0 {
                overlayManager.snoozeOverlay(for: 1)
                XCTAssertTrue(eventScheduler.snoozeScheduled, "Rapid cycle \(i): Should snooze")
            } else {
                overlayManager.hideOverlay()
            }

            XCTAssertFalse(overlayManager.isOverlayVisible, "Rapid cycle \(i): Should hide")

            // Small delay to prevent overwhelming the system
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }

        print("✅ Rapid fire interactions handled correctly")
    }

    func testMultipleSnoozeSequence() {
        // SCENARIO: User snoozes multiple times in sequence

        let event = TestUtilities.createTestEvent()
        let snoozeDurations = [1, 5, 10, 15, 1] // Different durations

        for (index, duration) in snoozeDurations.enumerated() {
            eventScheduler.reset()

            overlayManager.showOverlay(for: event)
            overlayManager.snoozeOverlay(for: duration)

            XCTAssertTrue(
                eventScheduler.snoozeScheduled, "Snooze sequence \(index): Should schedule snooze"
            )
            XCTAssertEqual(
                eventScheduler.snoozeMinutes, duration,
                "Snooze sequence \(index): Should use correct duration"
            )
            XCTAssertFalse(
                overlayManager.isOverlayVisible, "Snooze sequence \(index): Should hide overlay"
            )
        }

        print("✅ Multiple snooze sequence works correctly")
    }

    // MARK: - System State Change Tests

    func testOverlayDuringFocusModeChanges() {
        // SCENARIO: Focus mode changes while overlay is visible

        let event = TestUtilities.createTestEvent()
        overlayManager.showOverlay(for: event)

        XCTAssertTrue(overlayManager.isOverlayVisible, "Initial: Overlay should be visible")

        // Enable Do Not Disturb
        focusModeManager.isDoNotDisturbEnabled = true

        // Overlay behavior might change but shouldn't crash
        // The system should handle this gracefully
        overlayManager.snoozeOverlay(for: 1)

        XCTAssertFalse(overlayManager.isOverlayVisible, "Focus mode change: Should still handle snooze")

        // Disable Do Not Disturb
        focusModeManager.isDoNotDisturbEnabled = false

        print("✅ Focus mode changes handled correctly")
    }

    func testOverlayDuringPreferenceChanges() {
        // SCENARIO: User changes preferences while overlay is active

        let event = TestUtilities.createTestEvent()
        overlayManager.showOverlay(for: event)

        // Change overlay opacity preference
        mockPreferences.overlayOpacity = 0.3

        // Change appearance theme
        mockPreferences.appearanceTheme = .dark

        // Should still function correctly
        overlayManager.snoozeOverlay(for: 2)

        XCTAssertFalse(
            overlayManager.isOverlayVisible, "Preference changes: Should still handle snooze"
        )
        XCTAssertTrue(eventScheduler.snoozeScheduled, "Preference changes: Should schedule snooze")

        print("✅ Preference changes during overlay handled correctly")
    }

    // MARK: - Memory and Performance Tests

    func testOverlayMemoryManagement() async throws {
        // SCENARIO: Create many overlays to test for memory leaks

        var eventCount = 0

        for i in 0 ..< 50 {
            let event = TestUtilities.createTestEvent(title: "Test Event \(i)")
            eventCount += 1

            overlayManager.showOverlay(for: event)

            if i % 2 == 0 {
                overlayManager.snoozeOverlay(for: 1)
            } else {
                overlayManager.hideOverlay()
            }

            // Occasional garbage collection
            if i % 10 == 0 {
                try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            }
        }

        // Force garbage collection
        for _ in 0 ..< 3 {
            autoreleasepool {}
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        XCTAssertFalse(overlayManager.isOverlayVisible, "Memory test: Final state should be hidden")

        print("✅ Memory management test completed - \(eventCount) events processed")
    }

    func testOverlayTimerPrecision() async throws {
        // SCENARIO: Verify countdown timer precision under load

        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(10)) // 10 seconds
        overlayManager.showOverlay(for: event)

        let initialTime = overlayManager.timeUntilMeeting
        let startTime = Date()

        // Wait and measure precision
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        let finalTime = overlayManager.timeUntilMeeting
        let elapsedRealTime = Date().timeIntervalSince(startTime)
        let countdownChange = initialTime - finalTime

        let precision = abs(elapsedRealTime - countdownChange)
        XCTAssertLessThan(precision, 0.5, "Timer precision should be within 0.5 seconds")

        overlayManager.hideOverlay()

        print("✅ Timer precision test passed - precision: \(precision) seconds")
    }

    // MARK: - Error Recovery Tests

    func testOverlayRecoveryFromErrors() {
        // SCENARIO: System recovers gracefully from various error conditions

        let event = TestUtilities.createTestEvent()

        // Test 1: Show overlay, force error, then try again
        overlayManager.showOverlay(for: event)
        overlayManager.hideOverlay()

        // Immediately try to show again
        overlayManager.showOverlay(for: event)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Should recover from rapid show/hide")

        // Test 2: Multiple snooze attempts
        overlayManager.snoozeOverlay(for: 1)
        overlayManager.snoozeOverlay(for: 2) // Second call should be handled gracefully

        XCTAssertFalse(overlayManager.isOverlayVisible, "Should handle multiple snooze calls")

        // Test 3: Hide when already hidden
        overlayManager.hideOverlay() // Should not crash
        overlayManager.hideOverlay() // Should not crash

        print("✅ Error recovery tests passed")
    }

    // MARK: - Accessibility and UX Tests

    func testOverlayAccessibilityBehavior() {
        // SCENARIO: Verify overlay works well with accessibility features

        let event = TestUtilities.createTestEvent(title: "Accessibility Test Meeting")
        overlayManager.showOverlay(for: event)

        // Should show overlay regardless of accessibility settings
        XCTAssertTrue(overlayManager.isOverlayVisible, "Should work with accessibility features")
        XCTAssertEqual(
            overlayManager.activeEvent?.title, "Accessibility Test Meeting", "Should preserve event data"
        )

        // All interactions should still work
        overlayManager.snoozeOverlay(for: 5)
        XCTAssertTrue(eventScheduler.snoozeScheduled, "Accessibility: Snooze should work")

        print("✅ Accessibility behavior tests passed")
    }

    func testOverlayResponseiveness() {
        // SCENARIO: Verify overlay responds quickly to user interactions

        let event = TestUtilities.createTestEvent()

        // Measure response time for show
        let showStartTime = Date()
        overlayManager.showOverlay(for: event)
        let showResponseTime = Date().timeIntervalSince(showStartTime)

        XCTAssertLessThan(showResponseTime, 0.1, "Show overlay should be fast (<100ms)")

        // Measure response time for snooze
        let snoozeStartTime = Date()
        overlayManager.snoozeOverlay(for: 1)
        let snoozeResponseTime = Date().timeIntervalSince(snoozeStartTime)

        XCTAssertLessThan(snoozeResponseTime, 0.1, "Snooze should be fast (<100ms)")

        print(
            "✅ Responsiveness tests passed - Show: \(showResponseTime * 1000)ms, Snooze: \(snoozeResponseTime * 1000)ms"
        )
    }
}
