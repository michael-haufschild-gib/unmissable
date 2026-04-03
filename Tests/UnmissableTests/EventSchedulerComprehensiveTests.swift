import Combine
import TestSupport
@testable import Unmissable
import XCTest

@MainActor
final class EventSchedulerComprehensiveTests: XCTestCase {
    private var eventScheduler: EventScheduler!
    private var mockPreferences: PreferencesManager!
    private var overlayManager: TestSafeOverlayManager!
    private var cancellables = Set<AnyCancellable>()
    private var testClock: TestClock?

    override func setUp() async throws {
        try await super.setUp()

        mockPreferences = TestUtilities.createTestPreferencesManager()
        mockPreferences.testOverlayShowMinutesBefore = 2
        eventScheduler = EventScheduler(preferencesManager: mockPreferences, linkParser: LinkParser())
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        cancellables.removeAll()
        testClock = nil
    }

    /// Creates an EventScheduler with a controllable TestClock.
    /// Use for tests that would otherwise wait on real `Task.sleep`.
    private func createClockInjectedScheduler() -> (EventScheduler, TestClock) {
        let clock = TestClock(startTime: Date(), autoAdvance: true)
        let scheduler = EventScheduler(
            preferencesManager: mockPreferences,
            linkParser: LinkParser(),
            sleepForSeconds: clock.sleep,
            now: clock.nowProvider,
        )
        testClock = clock
        return (scheduler, clock)
    }

    override func tearDown() async throws {
        // Stop all scheduling operations and clean up timers
        eventScheduler.stopScheduling()
        cancellables.removeAll()

        // Give timers time to clean up
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in true }

        eventScheduler = nil
        overlayManager = nil
        mockPreferences = nil
        testClock = nil

        try await super.tearDown()
    }

    // MARK: - Basic Scheduling Tests

    func testBasicEventScheduling() async throws {
        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(300), // 5 minutes from now
        )

        await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

        // Should have scheduled alerts (may include both overlay and sound alerts)
        XCTAssertGreaterThanOrEqual(eventScheduler.scheduledAlerts.count, 1)

        let alert = try XCTUnwrap(eventScheduler.scheduledAlerts.first)
        XCTAssertEqual(alert.event.id, futureEvent.id)

        if case let .reminder(minutes) = alert.alertType {
            XCTAssertEqual(minutes, mockPreferences.overlayShowMinutesBefore)
        } else {
            XCTFail("Expected reminder alert type")
        }
    }

    func testStartScheduling_acceptsOverlayManagingExistential() async {
        let testOverlay = TestSafeOverlayManager(isTestEnvironment: true)
        testOverlay.setEventScheduler(eventScheduler)
        let protocolOverlayManager: any OverlayManaging = testOverlay

        let upcomingEvent = TestUtilities.createTestEvent(
            id: "protocol-overlay-event",
            startDate: Date().addingTimeInterval(30),
            endDate: Date().addingTimeInterval(1800),
        )

        await eventScheduler.startScheduling(
            events: [upcomingEvent],
            overlayManager: protocolOverlayManager,
        )

        XCTAssertTrue(protocolOverlayManager.isOverlayVisible)
        XCTAssertEqual(protocolOverlayManager.activeEvent?.id, upcomingEvent.id)
    }

    func testPastEventNotScheduled() async {
        let pastEvent = TestUtilities.createPastEvent()

        await eventScheduler.startScheduling(events: [pastEvent], overlayManager: overlayManager)

        // Should not schedule alerts for past events
        XCTAssertEqual(eventScheduler.scheduledAlerts, [], "Past events should produce no alerts")
    }

    func testMultipleEventsScheduling() async {
        let event1 = TestUtilities.createTestEvent(
            id: "event1",
            startDate: Date().addingTimeInterval(300),
        )
        let event2 = TestUtilities.createTestEvent(
            id: "event2",
            startDate: Date().addingTimeInterval(600),
        )

        await eventScheduler.startScheduling(
            events: [event1, event2], overlayManager: overlayManager,
        )

        XCTAssertGreaterThanOrEqual(eventScheduler.scheduledAlerts.count, 2)

        // Alerts should be sorted by trigger time
        let sortedAlerts = eventScheduler.scheduledAlerts.sorted { $0.triggerDate < $1.triggerDate }
        XCTAssertEqual(
            eventScheduler.scheduledAlerts.map(\.triggerDate), sortedAlerts.map(\.triggerDate),
        )
    }

    // MARK: - Preferences Integration Tests

    func testPreferenceChangesRescheduleAlerts() async {
        // This test validates that EventScheduler uses the correct preferences
        // when scheduling alerts, which is critical for avoiding notification spam

        // Create a test preferences with specific values
        let testPreferences = PreferencesManager(themeManager: ThemeManager())
        testPreferences.setOverlayShowMinutesBefore(10)
        testPreferences.setDefaultAlertMinutes(10)
        testPreferences.setShortMeetingAlertMinutes(10)
        testPreferences.setMediumMeetingAlertMinutes(10)
        testPreferences.setLongMeetingAlertMinutes(10)

        // Verify the preference returns the correct value
        XCTAssertEqual(
            testPreferences.overlayShowMinutesBefore, 10, "Test preferences should return 10",
        )

        // Create a new EventScheduler with our test preferences
        let testScheduler = EventScheduler(preferencesManager: testPreferences, linkParser: LinkParser())

        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(1200), // 20 minutes from now (enough for 10-minute alert)
        )

        // Schedule with the test preferences
        await testScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

        // Verify we got scheduled alerts
        XCTAssertGreaterThanOrEqual(
            testScheduler.scheduledAlerts.count, 1, "Should have at least one scheduled alert",
        )

        let reminderAlerts = testScheduler.scheduledAlerts.filter {
            if case .reminder = $0.alertType { true } else { false }
        }
        XCTAssertGreaterThanOrEqual(reminderAlerts.count, 1, "Should have at least one reminder alert")

        guard let firstAlert = reminderAlerts.first else {
            XCTFail("Expected reminder alert type")
            return
        }

        if case let .reminder(minutes) = firstAlert.alertType {
            XCTAssertEqual(minutes, 10, "EventScheduler should use the specified preference value")
        } else {
            XCTFail("Expected reminder alert type")
        }

        // Clean up
        testScheduler.stopScheduling()
    }

    func testLengthBasedTimingPreferences() async throws {
        // Create events of different lengths
        let shortEvent = TestUtilities.createTestEvent(
            id: "short",
            startDate: Date().addingTimeInterval(900), // 15 minutes from now
            endDate: Date().addingTimeInterval(1800), // 30 minutes total (15 min duration)
        )

        let longEvent = TestUtilities.createTestEvent(
            id: "long",
            startDate: Date().addingTimeInterval(1200), // 20 minutes from now
            endDate: Date().addingTimeInterval(7200), // 2 hours total (100 min duration)
        )

        // Enable length-based timing
        mockPreferences.testUseLengthBasedTiming = true
        mockPreferences.setShortMeetingAlertMinutes(2)
        mockPreferences.setLongMeetingAlertMinutes(10)

        await eventScheduler.startScheduling(
            events: [shortEvent, longEvent], overlayManager: overlayManager,
        )

        // Verify different timing for different event lengths
        let shortAlert = try XCTUnwrap(eventScheduler.scheduledAlerts.first { $0.event.id == "short" })
        let longAlert = try XCTUnwrap(eventScheduler.scheduledAlerts.first { $0.event.id == "long" })

        // Long events should have different timing than short events
        XCTAssertNotEqual(shortAlert.triggerDate, longAlert.triggerDate)
    }

    // MARK: - Sound Alert Tests

    func testSoundAlertsWhenEnabled() async {
        mockPreferences.testSoundEnabled = true
        mockPreferences.testDefaultAlertMinutes = 3
        mockPreferences.testOverlayShowMinutesBefore = 5

        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(600), // 10 minutes from now
        )

        await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

        // Should have both overlay and sound alerts when timings differ
        let alerts = eventScheduler.scheduledAlerts
        let reminderAlerts = alerts.filter {
            if case .reminder = $0.alertType { return true }
            return false
        }
        // Both alerts should be reminders for the same event with different timings
        XCTAssertEqual(Set(alerts.map(\.event.id)), Set([futureEvent.id]))
        XCTAssertEqual(reminderAlerts.map(\.event.id), [futureEvent.id, futureEvent.id])
    }

    func testNoSoundAlertsWhenDisabled() async {
        mockPreferences.testSoundEnabled = false

        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(600),
        )

        await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

        // Should only have overlay alert, no sound alert
        XCTAssertEqual(eventScheduler.scheduledAlerts.map(\.event.id), [futureEvent.id])
    }

    // MARK: - Snooze Tests

    func testSnoozeScheduling() throws {
        let event = TestUtilities.createTestEvent()

        eventScheduler.scheduleSnooze(for: event, minutes: 5)

        let snoozeAlert = try XCTUnwrap(eventScheduler.scheduledAlerts.first)
        XCTAssertEqual(snoozeAlert.event.id, event.id)
        if case let .snooze(until) = snoozeAlert.alertType {
            let expectedTime = Date().addingTimeInterval(5 * 60)
            let timeDifference = abs(until.timeIntervalSince(expectedTime))
            XCTAssertLessThan(timeDifference, 2.0) // Allow 2 second tolerance
        } else {
            XCTFail("Expected snooze alert type")
        }
    }

    func testSnoozePreservedDuringRescheduling() async throws {
        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(600),
        )

        await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

        // Add a snooze
        eventScheduler.scheduleSnooze(for: futureEvent, minutes: 3)
        _ = eventScheduler.scheduledAlerts.count // Check that snooze was added

        // Change preferences to trigger rescheduling
        mockPreferences.testOverlayShowMinutesBefore = 8

        // Wait for rescheduling
        let scheduler = try XCTUnwrap(eventScheduler)
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            return scheduler.scheduledAlerts.contains { alert in
                if case .snooze = alert.alertType { return true }
                return false
            }
        }

        // Snooze alert should still be present
        let hasSnoozeAlert = eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }

        XCTAssertTrue(hasSnoozeAlert, "Snooze alert should be preserved during rescheduling")
    }

    // MARK: - Timer Memory Management Tests

    func testStopSchedulingClearsTimers() async {
        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(300),
        )

        await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)
        XCTAssertGreaterThanOrEqual(eventScheduler.scheduledAlerts.count, 1)

        eventScheduler.stopScheduling()

        XCTAssertEqual(eventScheduler.scheduledAlerts, [], "All alerts should be cleared after stop")
    }

    func testMemoryCleanupSimple() async throws {
        // First test if memory leak detection works with a simple object
        class SimpleTestObject {
            var value = 42
        }

        var simpleObject: SimpleTestObject? = SimpleTestObject()
        weak var weakSimple: SimpleTestObject?
        weakSimple = simpleObject
        simpleObject = nil

        XCTAssertNil(weakSimple, "Simple object should be deallocated")

        // Now test EventScheduler with minimal setup
        let testPreferences = PreferencesManager(themeManager: ThemeManager())

        var scheduler: EventScheduler? = EventScheduler(preferencesManager: testPreferences, linkParser: LinkParser())
        weak var weakScheduler: EventScheduler?
        weakScheduler = scheduler

        // Clean up reference immediately
        scheduler = nil

        // Give longer time for cleanup
        try await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            weakScheduler == nil
        }

        XCTAssertNil(weakScheduler, "EventScheduler should be deallocated after cleanup")
    } // MARK: - Alert Triggering Tests

    func testAlertTriggering() async throws {
        let (scheduler, clock) = createClockInjectedScheduler()
        eventScheduler = scheduler

        let baseTime = clock.currentTime
        let nearFutureEvent = TestUtilities.createTestEvent(
            startDate: baseTime.addingTimeInterval(30), // 30 seconds from clock's "now"
        )

        // Set overlay timing to 0 — alert triggers at event start time (baseTime + 30s)
        mockPreferences.testOverlayShowMinutesBefore = 0

        await scheduler.startScheduling(
            events: [nearFutureEvent], overlayManager: overlayManager,
        )

        // The monitoring loop will sleep for ~30s via the test clock.
        // autoAdvance advances clock.currentTime by 30s instantly.
        // After the sleep returns, checkForTriggeredAlerts runs with
        // clock time at ~baseTime+30s, finding the alert due.
        let overlay = try XCTUnwrap(overlayManager)
        try await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            overlay.isOverlayVisible && overlay.activeEvent?.id == nearFutureEvent.id
        }

        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, nearFutureEvent.id)
    }

    func testReminderTriggerDoesNotApplyHardcodedFiveMinuteDelay() async throws {
        let (scheduler, clock) = createClockInjectedScheduler()
        eventScheduler = scheduler

        mockPreferences.testOverlayShowMinutesBefore = 6
        mockPreferences.testSoundEnabled = false

        let baseTime = clock.currentTime
        let event = TestUtilities.createTestEvent(
            id: "trigger-no-hardcoded-delay",
            startDate: baseTime.addingTimeInterval(TimeInterval(6 * 60) + 2),
        )

        await scheduler.startScheduling(events: [event], overlayManager: overlayManager)

        // Test clock auto-advances through the ~2s sleep instantly.
        // The alert fires at baseTime + 2s (6 min before event, overlay shows 6 min before).
        let overlay = try XCTUnwrap(overlayManager)
        try await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            overlay.isOverlayVisible && overlay.activeEvent?.id == event.id
        }

        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, event.id)
    }

    // MARK: - Edge Cases

    func testEndedEventsAreSkipped() async {
        let endedEvent = TestUtilities.createTestEvent(
            id: "ended",
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-3600),
        )

        await eventScheduler.startScheduling(events: [endedEvent], overlayManager: overlayManager)
        XCTAssertTrue(
            eventScheduler.scheduledAlerts.isEmpty,
            "Events that have already ended should not produce alerts",
        )
    }

    func testIdenticalOverlayAndSoundTimingProducesSingleAlert() async {
        // When overlay and sound alert timing are the same, only 1 alert should be created
        mockPreferences.testSoundEnabled = true
        mockPreferences.testDefaultAlertMinutes = 5
        mockPreferences.testOverlayShowMinutesBefore = 5

        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(600), // 10 min from now
        )

        await eventScheduler.startScheduling(events: [event], overlayManager: overlayManager)

        // Should have exactly 1 alert, not 2, since timings are identical
        XCTAssertEqual(
            eventScheduler.scheduledAlerts.map(\.event.id),
            [event.id],
            "Equal overlay and sound timing should produce 1 alert, not 2",
        )
    }

    func testAllDayEventsWithPastStartAreNotScheduled() async {
        let allDay = TestUtilities.createAllDayEvent()

        await eventScheduler.startScheduling(events: [allDay], overlayManager: overlayManager)

        // All-day events that have already started (startDate at beginning of today):
        // - Alert time is in the past
        // - startDate is also in the past
        // The scheduler correctly skips these — they don't qualify as "missed alerts"
        // because the meeting has already started. This prevents surprise overlays
        // for all-day events the user is already aware of.
        XCTAssertEqual(
            eventScheduler.scheduledAlerts,
            [],
            "All-day events with past startDate should not produce alerts",
        )
    }

    func testZeroDurationEventScheduled() async {
        let now = Date()
        let zeroDuration = TestUtilities.createTestEvent(
            id: "zero-dur",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(600), // same as start
        )

        await eventScheduler.startScheduling(events: [zeroDuration], overlayManager: overlayManager)

        // Zero duration event is valid (e.g. a reminder) — should still get an alert
        let alerts = eventScheduler.scheduledAlerts
        XCTAssertGreaterThanOrEqual(alerts.count, 1, "Zero duration event should produce at least one alert")
        XCTAssertEqual(alerts.first?.event.id, "zero-dur")
    }

    func testNegativeSnoozeMinutesHandled() {
        let event = TestUtilities.createTestEvent()
        // Scheduling a negative snooze should not crash
        eventScheduler.scheduleSnooze(for: event, minutes: -5)

        // The snooze should still be created (the scheduler doesn't validate duration)
        let alerts = eventScheduler.scheduledAlerts
        XCTAssertGreaterThanOrEqual(alerts.count, 1, "Negative snooze should still create an alert")
        XCTAssertEqual(alerts.first?.event.id, event.id)
    }

    // MARK: - Performance Tests

    func testLargeNumberOfEvents() async throws {
        let numberOfEvents = 100
        let events = (0 ..< numberOfEvents).map { index in
            TestUtilities.createTestEvent(
                id: "event-\(index)",
                startDate: Date()
                    .addingTimeInterval(Double(index * 60 + 300)), // Start 5 minutes from now, spaced 1 minute apart
            )
        }

        let scheduler = try XCTUnwrap(eventScheduler)
        let overlay = try XCTUnwrap(overlayManager)
        let (_, schedulingTime) = await TestUtilities.measureTimeAsync { @MainActor @Sendable in
            await scheduler.startScheduling(
                events: events, overlayManager: overlay,
            )
        }

        // Scheduling should complete quickly even with many events
        XCTAssertLessThan(schedulingTime, 1.0, "Scheduling 100 events should take less than 1 second")

        // Should have alerts for all future events (may include multiple alert types per event)
        XCTAssertGreaterThanOrEqual(eventScheduler.scheduledAlerts.count, numberOfEvents)
    }
}
