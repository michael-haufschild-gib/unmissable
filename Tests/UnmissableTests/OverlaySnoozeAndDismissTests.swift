import Foundation
import Testing
@testable import Unmissable

/// Tests for overlay snooze and dismiss functionality
@MainActor
struct OverlaySnoozeAndDismissTests {
    private var overlayManager: TestSafeOverlayManager
    private var mockPreferences: PreferencesManager
    private var eventScheduler: EventScheduler

    init() {
        let prefs = TestUtilities.createTestPreferencesManager()
        let om = TestSafeOverlayManager(isTestEnvironment: true)
        let es = EventScheduler(preferencesManager: prefs, linkParser: LinkParser())
        om.setEventScheduler(es)
        mockPreferences = prefs
        overlayManager = om
        eventScheduler = es
    }

    // MARK: - Snooze Functionality Tests

    @Test
    func snoozeOverlayHidesOverlay() throws {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)
        #expect(overlayManager.isOverlayVisible, "Overlay should be visible initially")
        let activeEvent = try #require(overlayManager.activeEvent)
        #expect(activeEvent.id == event.id)

        overlayManager.snoozeOverlay(for: 5)

        #expect(!overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")
        #expect(overlayManager.activeEvent == nil, "Active event should be cleared after snooze")
    }

    @Test
    func snoozeOverlaySchedulesCorrectSnoozeAlert() throws {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent(
            title: "Important Meeting",
            startDate: Date().addingTimeInterval(600),
        )

        overlayManager.showOverlayImmediately(for: event)

        let snoozeMinutes = 3
        overlayManager.snoozeOverlay(for: snoozeMinutes)

        #expect(eventScheduler.snoozeScheduled, "Snooze should be scheduled")
        #expect(eventScheduler.snoozeMinutes == snoozeMinutes, "Should schedule correct snooze duration")
        #expect(eventScheduler.snoozeEvent?.id == event.id, "Should schedule snooze for correct event")

        let expectedSnoozeTime = Date().addingTimeInterval(TimeInterval(snoozeMinutes * 60))
        let actualSnoozeTime = try #require(eventScheduler.snoozeTime)
        let timeDifference = abs(expectedSnoozeTime.timeIntervalSince(actualSnoozeTime))
        #expect(timeDifference < 5.0, "Snooze time should be approximately correct")
    }

    @Test
    func snoozeWithDifferentDurations() {
        defer { overlayManager.hideOverlay() }
        let testDurations = [1, 5, 10, 15]

        for duration in testDurations {
            eventScheduler.stopScheduling()

            let event = TestUtilities.createTestEvent(title: "Test Meeting \(duration)")
            overlayManager.showOverlayImmediately(for: event)
            overlayManager.snoozeOverlay(for: duration)

            #expect(eventScheduler.snoozeScheduled, "Snooze should be scheduled for \(duration) minutes")
            #expect(
                eventScheduler.snoozeMinutes == duration, "Should schedule correct duration: \(duration) minutes",
            )
            #expect(
                !overlayManager.isOverlayVisible, "Overlay should be hidden after \(duration)-minute snooze",
            )
        }
    }

    @Test
    func snoozeOverlayResetsCountdownToZero() {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)
        #expect(overlayManager.timeUntilMeeting > 0, "Countdown should be active before snooze")

        overlayManager.snoozeOverlay(for: 5)

        // After snooze, activeEvent is nil so timeUntilMeeting returns 0
        #expect(overlayManager.timeUntilMeeting == 0, "Countdown should be zero after snooze")
    }

    // MARK: - Dismiss Functionality Tests

    @Test
    func dismissOverlayHidesOverlay() throws {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)
        #expect(overlayManager.isOverlayVisible, "Overlay should be visible initially")
        let activeEvent = try #require(overlayManager.activeEvent)
        #expect(activeEvent.id == event.id)

        overlayManager.hideOverlay()

        #expect(!overlayManager.isOverlayVisible, "Overlay should be hidden after dismiss")
        #expect(overlayManager.activeEvent == nil, "Active event should be cleared after dismiss")
    }

    @Test
    func dismissOverlayResetsCountdownToZero() {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)
        #expect(overlayManager.timeUntilMeeting > 0, "Countdown should be active before dismiss")

        overlayManager.hideOverlay()

        // After dismiss, activeEvent is nil so timeUntilMeeting returns 0
        #expect(overlayManager.timeUntilMeeting == 0, "Countdown should be zero after dismiss")
    }

    @Test
    func dismissResetsTimeUntilMeetingToZero() async throws {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600))

        overlayManager.showOverlayImmediately(for: event)
        try await TestUtilities.waitForAsync(timeout: 10.0) { @MainActor @Sendable in
            overlayManager.timeUntilMeeting > 0
        }
        #expect(overlayManager.timeUntilMeeting > 590, "Should be close to 10 minutes")

        overlayManager.hideOverlay()

        #expect(overlayManager.timeUntilMeeting == 0)
    }

    @Test
    func dismissDoesNotScheduleSnooze() {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)
        overlayManager.hideOverlay()

        #expect(!eventScheduler.snoozeScheduled, "Dismiss should not schedule snooze")
        #expect(eventScheduler.snoozeEvent == nil, "No snooze event should be set")
    }

    // MARK: - Rapid Interaction Tests

    @Test
    func rapidSnoozeAndDismissInteractions() {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        for i in 0 ..< 5 {
            eventScheduler.stopScheduling()
            overlayManager.showOverlayImmediately(for: event)
            #expect(overlayManager.isOverlayVisible, "Overlay should show for iteration \(i)")

            if i.isMultiple(of: 2) {
                overlayManager.snoozeOverlay(for: 1)
                #expect(eventScheduler.snoozeScheduled, "Snooze should work on iteration \(i)")
            } else {
                overlayManager.hideOverlay()
                #expect(!eventScheduler.snoozeScheduled, "Dismiss should work on iteration \(i)")
            }

            #expect(!overlayManager.isOverlayVisible, "Overlay should be hidden after iteration \(i)")
        }
    }

    @Test
    func snoozeWhileOverlayNotVisible() {
        #expect(!overlayManager.isOverlayVisible, "Overlay should not be visible initially")

        overlayManager.snoozeOverlay(for: 5)

        #expect(!overlayManager.isOverlayVisible, "Overlay should still not be visible")
        #expect(!eventScheduler.snoozeScheduled, "No snooze should be scheduled when no overlay is active")
    }

    // MARK: - Error Handling Tests

    @Test
    func snoozeWithInvalidDuration() {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)
        overlayManager.snoozeOverlay(for: 0)
        #expect(!overlayManager.isOverlayVisible, "Overlay should be hidden even with 0-minute snooze")
        #expect(eventScheduler.snoozeScheduled, "Zero-minute snooze should still schedule (clamped to 1)")
        #expect(eventScheduler.snoozeMinutes == 1, "Zero minutes should be clamped to minimum of 1")

        eventScheduler.stopScheduling()
        overlayManager.showOverlayImmediately(for: event)
        overlayManager.snoozeOverlay(for: 1440) // 24 hours

        #expect(eventScheduler.snoozeScheduled, "Large snooze duration should still work")
        #expect(eventScheduler.snoozeMinutes == 1440, "Should handle large durations")
    }

    @Test
    func repeatedSnoozeAndDismissCallsRemainIdempotent() {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)
        overlayManager.snoozeOverlay(for: 1)

        let firstSnoozeMinutes = eventScheduler.snoozeMinutes
        overlayManager.snoozeOverlay(for: 2) // No active event, should be a no-op

        overlayManager.hideOverlay()
        overlayManager.hideOverlay()

        #expect(!overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent == nil)
        #expect(eventScheduler.snoozeMinutes == firstSnoozeMinutes)
    }

    // MARK: - State Consistency Tests

    @Test
    func overlayStateConsistencyAfterSnooze() {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)

        #expect(overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent?.id == event.id)
        #expect(overlayManager.timeUntilMeeting > 290, "Should be close to 5 minutes")

        overlayManager.snoozeOverlay(for: 5)

        #expect(!overlayManager.isOverlayVisible, "isOverlayVisible should be false")
        #expect(overlayManager.activeEvent == nil, "activeEvent should be nil")
        #expect(overlayManager.timeUntilMeeting == 0, "Countdown should be zero after snooze")
    }

    @Test
    func overlayStateConsistencyAfterDismiss() {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)

        #expect(overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent?.id == event.id)

        overlayManager.hideOverlay()

        #expect(!overlayManager.isOverlayVisible, "isOverlayVisible should be false")
        #expect(overlayManager.activeEvent == nil, "activeEvent should be nil")
        #expect(overlayManager.timeUntilMeeting == 0, "Countdown should be zero after dismiss")
    }
}
