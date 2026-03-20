import Combine
@testable import Unmissable
import XCTest

/// Tests for overlay snooze and dismiss functionality
@MainActor
final class OverlaySnoozeAndDismissTests: XCTestCase {
    private var overlayManager: TestSafeOverlayManager?
    private var mockPreferences: PreferencesManager?
    private var eventScheduler: EventScheduler?
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        let prefs = TestUtilities.createTestPreferencesManager()
        let om = TestSafeOverlayManager(isTestEnvironment: true)
        let es = EventScheduler(preferencesManager: prefs)
        om.setEventScheduler(es)
        mockPreferences = prefs
        overlayManager = om
        eventScheduler = es
        cancellables.removeAll()
        try await super.setUp()
    }

    override func tearDown() async throws {
        overlayManager?.hideOverlay()
        cancellables.removeAll()
        overlayManager = nil
        eventScheduler = nil
        mockPreferences = nil
        try await super.tearDown()
    }

    // MARK: - Snooze Functionality Tests

    func testSnoozeOverlayHidesOverlay() throws {
        let om = try XCTUnwrap(overlayManager)
        let event = TestUtilities.createTestEvent()

        om.showOverlayImmediately(for: event)
        XCTAssertTrue(om.isOverlayVisible, "Overlay should be visible initially")
        let activeEvent = try XCTUnwrap(om.activeEvent)
        XCTAssertEqual(activeEvent.id, event.id)

        om.snoozeOverlay(for: 5)

        XCTAssertFalse(om.isOverlayVisible, "Overlay should be hidden after snooze")
        XCTAssertNil(om.activeEvent, "Active event should be cleared after snooze")
    }

    func testSnoozeOverlaySchedulesCorrectSnoozeAlert() throws {
        let om = try XCTUnwrap(overlayManager)
        let es = try XCTUnwrap(eventScheduler)
        let event = TestUtilities.createTestEvent(
            title: "Important Meeting",
            startDate: Date().addingTimeInterval(600)
        )

        om.showOverlayImmediately(for: event)

        let snoozeMinutes = 3
        om.snoozeOverlay(for: snoozeMinutes)

        XCTAssertTrue(es.snoozeScheduled, "Snooze should be scheduled")
        XCTAssertEqual(es.snoozeMinutes, snoozeMinutes, "Should schedule correct snooze duration")
        XCTAssertEqual(es.snoozeEvent?.id, event.id, "Should schedule snooze for correct event")

        let expectedSnoozeTime = Date().addingTimeInterval(TimeInterval(snoozeMinutes * 60))
        let actualSnoozeTime = try XCTUnwrap(es.snoozeTime)
        let timeDifference = abs(expectedSnoozeTime.timeIntervalSince(actualSnoozeTime))
        XCTAssertLessThan(timeDifference, 5.0, "Snooze time should be approximately correct")
    }

    func testSnoozeWithDifferentDurations() throws {
        let om = try XCTUnwrap(overlayManager)
        let es = try XCTUnwrap(eventScheduler)
        let testDurations = [1, 5, 10, 15]

        for duration in testDurations {
            es.reset()

            let event = TestUtilities.createTestEvent(title: "Test Meeting \(duration)")
            om.showOverlayImmediately(for: event)
            om.snoozeOverlay(for: duration)

            XCTAssertTrue(es.snoozeScheduled, "Snooze should be scheduled for \(duration) minutes")
            XCTAssertEqual(
                es.snoozeMinutes, duration, "Should schedule correct duration: \(duration) minutes"
            )
            XCTAssertFalse(
                om.isOverlayVisible, "Overlay should be hidden after \(duration)-minute snooze"
            )
        }
    }

    func testSnoozeOverlayStopsCountdownTimer() async throws {
        let om = try XCTUnwrap(overlayManager)
        let event = TestUtilities.createTestEvent()

        om.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            om.timeUntilMeeting > 0
        }

        om.snoozeOverlay(for: 5)
        let countdownAfterSnooze = om.timeUntilMeeting

        // Verify timer stopped by waiting and checking value hasn't changed
        try? await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            om.timeUntilMeeting != countdownAfterSnooze
        }

        XCTAssertEqual(countdownAfterSnooze, om.timeUntilMeeting, "Timer should stop after snooze")
    }

    // MARK: - Dismiss Functionality Tests

    func testDismissOverlayHidesOverlay() throws {
        let om = try XCTUnwrap(overlayManager)
        let event = TestUtilities.createTestEvent()

        om.showOverlayImmediately(for: event)
        XCTAssertTrue(om.isOverlayVisible, "Overlay should be visible initially")
        let activeEvent = try XCTUnwrap(om.activeEvent)
        XCTAssertEqual(activeEvent.id, event.id)

        om.hideOverlay()

        XCTAssertFalse(om.isOverlayVisible, "Overlay should be hidden after dismiss")
        XCTAssertNil(om.activeEvent, "Active event should be cleared after dismiss")
    }

    func testDismissOverlayStopsCountdownTimer() async throws {
        let om = try XCTUnwrap(overlayManager)
        let event = TestUtilities.createTestEvent()

        om.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            om.timeUntilMeeting > 0
        }

        om.hideOverlay()
        let countdownAfterDismiss = om.timeUntilMeeting

        try? await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            om.timeUntilMeeting != countdownAfterDismiss
        }

        XCTAssertEqual(countdownAfterDismiss, om.timeUntilMeeting, "Timer should stop after dismiss")
    }

    func testDismissResetsTimeUntilMeetingToZero() async throws {
        let om = try XCTUnwrap(overlayManager)
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600))

        om.showOverlayImmediately(for: event)
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            om.timeUntilMeeting > 0
        }
        XCTAssertGreaterThan(om.timeUntilMeeting, 0)

        om.hideOverlay()

        XCTAssertEqual(om.timeUntilMeeting, 0)
    }

    func testDismissDoesNotScheduleSnooze() throws {
        let om = try XCTUnwrap(overlayManager)
        let es = try XCTUnwrap(eventScheduler)
        let event = TestUtilities.createTestEvent()

        om.showOverlayImmediately(for: event)
        om.hideOverlay()

        XCTAssertFalse(es.snoozeScheduled, "Dismiss should not schedule snooze")
        XCTAssertNil(es.snoozeEvent, "No snooze event should be set")
    }

    // MARK: - Rapid Interaction Tests

    func testRapidSnoozeAndDismissInteractions() throws {
        let om = try XCTUnwrap(overlayManager)
        let es = try XCTUnwrap(eventScheduler)
        let event = TestUtilities.createTestEvent()

        for i in 0 ..< 5 {
            es.reset()
            om.showOverlayImmediately(for: event)
            XCTAssertTrue(om.isOverlayVisible, "Overlay should show for iteration \(i)")

            if i % 2 == 0 {
                om.snoozeOverlay(for: 1)
                XCTAssertTrue(es.snoozeScheduled, "Snooze should work on iteration \(i)")
            } else {
                om.hideOverlay()
                XCTAssertFalse(es.snoozeScheduled, "Dismiss should work on iteration \(i)")
            }

            XCTAssertFalse(om.isOverlayVisible, "Overlay should be hidden after iteration \(i)")
        }
    }

    func testSnoozeWhileOverlayNotVisible() throws {
        let om = try XCTUnwrap(overlayManager)
        let es = try XCTUnwrap(eventScheduler)
        XCTAssertFalse(om.isOverlayVisible, "Overlay should not be visible initially")

        om.snoozeOverlay(for: 5)

        XCTAssertFalse(om.isOverlayVisible, "Overlay should still not be visible")
        XCTAssertFalse(es.snoozeScheduled, "No snooze should be scheduled when no overlay is active")
    }

    // MARK: - Error Handling Tests

    func testSnoozeWithInvalidDuration() throws {
        let om = try XCTUnwrap(overlayManager)
        let es = try XCTUnwrap(eventScheduler)
        let event = TestUtilities.createTestEvent()

        om.showOverlayImmediately(for: event)
        om.snoozeOverlay(for: 0)
        XCTAssertFalse(om.isOverlayVisible, "Overlay should be hidden even with 0-minute snooze")

        es.reset()
        om.showOverlayImmediately(for: event)
        om.snoozeOverlay(for: 1440) // 24 hours

        XCTAssertTrue(es.snoozeScheduled, "Large snooze duration should still work")
        XCTAssertEqual(es.snoozeMinutes, 1440, "Should handle large durations")
    }

    func testRepeatedSnoozeAndDismissCallsRemainIdempotent() throws {
        let om = try XCTUnwrap(overlayManager)
        let es = try XCTUnwrap(eventScheduler)
        let event = TestUtilities.createTestEvent()

        om.showOverlayImmediately(for: event)
        om.snoozeOverlay(for: 1)

        let firstSnoozeMinutes = es.snoozeMinutes
        om.snoozeOverlay(for: 2) // No active event, should be a no-op

        om.hideOverlay()
        om.hideOverlay()

        XCTAssertFalse(om.isOverlayVisible)
        XCTAssertNil(om.activeEvent)
        XCTAssertEqual(es.snoozeMinutes, firstSnoozeMinutes)
    }

    // MARK: - State Consistency Tests

    func testOverlayStateConsistencyAfterSnooze() async throws {
        let om = try XCTUnwrap(overlayManager)
        let event = TestUtilities.createTestEvent()

        om.showOverlayImmediately(for: event)

        XCTAssertTrue(om.isOverlayVisible)
        XCTAssertEqual(om.activeEvent?.id, event.id)
        XCTAssertGreaterThan(om.timeUntilMeeting, 0)

        om.snoozeOverlay(for: 5)

        XCTAssertFalse(om.isOverlayVisible, "isOverlayVisible should be false")
        XCTAssertNil(om.activeEvent, "activeEvent should be nil")

        let countdownAfterSnooze = om.timeUntilMeeting
        try? await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            om.timeUntilMeeting != countdownAfterSnooze
        }

        XCTAssertEqual(
            countdownAfterSnooze, om.timeUntilMeeting, "Timer should not be running after snooze"
        )
    }

    func testOverlayStateConsistencyAfterDismiss() async throws {
        let om = try XCTUnwrap(overlayManager)
        let event = TestUtilities.createTestEvent()

        om.showOverlayImmediately(for: event)

        XCTAssertTrue(om.isOverlayVisible)
        XCTAssertEqual(om.activeEvent?.id, event.id)

        om.hideOverlay()

        XCTAssertFalse(om.isOverlayVisible, "isOverlayVisible should be false")
        XCTAssertNil(om.activeEvent, "activeEvent should be nil")

        let countdownAfterDismiss = om.timeUntilMeeting
        try? await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            om.timeUntilMeeting != countdownAfterDismiss
        }

        XCTAssertEqual(
            countdownAfterDismiss, om.timeUntilMeeting, "Timer should not be running after dismiss"
        )
    }
}
