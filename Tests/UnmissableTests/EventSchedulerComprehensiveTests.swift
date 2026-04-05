import Foundation
import Testing
@testable import Unmissable

@MainActor
struct EventSchedulerComprehensiveTests {
    private var eventScheduler: EventScheduler
    private var mockPreferences: PreferencesManager
    private var overlayManager: TestSafeOverlayManager

    init() {
        mockPreferences = TestUtilities.createTestPreferencesManager()
        mockPreferences.testOverlayShowMinutesBefore = 2
        eventScheduler = EventScheduler(preferencesManager: mockPreferences, linkParser: LinkParser())
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
    }

    /// Creates an EventScheduler with a controllable TestClock.
    /// Use for tests that would otherwise wait on real `Task.sleep`.
    private func createClockInjectedScheduler() -> (EventScheduler, TestClock) {
        let clock = TestClock(startTime: Date())
        let scheduler = EventScheduler(
            preferencesManager: mockPreferences,
            linkParser: LinkParser(),
            sleepForSeconds: clock.sleepForSeconds,
            now: clock.nowProvider,
        )
        return (scheduler, clock)
    }

    // MARK: - Basic Scheduling Tests

    @Test
    func basicEventScheduling() async throws {
        defer { eventScheduler.stopScheduling() }
        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(300), // 5 minutes from now
        )

        await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

        // Should have scheduled alerts (may include both overlay and sound alerts)
        #expect(eventScheduler.scheduledAlerts.count >= 1)

        let alert = try #require(eventScheduler.scheduledAlerts.first)
        #expect(alert.event.id == futureEvent.id)

        if case let .reminder(minutes) = alert.alertType {
            #expect(minutes == mockPreferences.overlayShowMinutesBefore)
        } else {
            Issue.record("Expected reminder alert type")
        }
    }

    @Test
    func startScheduling_acceptsOverlayManagingExistential() async {
        defer { eventScheduler.stopScheduling() }
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

        #expect(protocolOverlayManager.isOverlayVisible)
        #expect(protocolOverlayManager.activeEvent?.id == upcomingEvent.id)
    }

    @Test
    func pastEventNotScheduled() async {
        defer { eventScheduler.stopScheduling() }
        let pastEvent = TestUtilities.createPastEvent()

        await eventScheduler.startScheduling(events: [pastEvent], overlayManager: overlayManager)

        // Should not schedule alerts for past events
        #expect(eventScheduler.scheduledAlerts.isEmpty, "Past events should produce no alerts")
    }

    @Test
    func multipleEventsScheduling() async {
        defer { eventScheduler.stopScheduling() }
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

        #expect(eventScheduler.scheduledAlerts.count >= 2)

        // Alerts should be sorted by trigger time
        let sortedAlerts = eventScheduler.scheduledAlerts.sorted { $0.triggerDate < $1.triggerDate }
        #expect(
            eventScheduler.scheduledAlerts.map(\.triggerDate) == sortedAlerts.map(\.triggerDate),
        )
    }

    // MARK: - Preferences Integration Tests

    @Test
    func preferenceChangesRescheduleAlerts() async throws {
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
        #expect(testPreferences.overlayShowMinutesBefore == 10, "Test preferences should return 10")

        // Create a new EventScheduler with our test preferences
        let testScheduler = EventScheduler(preferencesManager: testPreferences, linkParser: LinkParser())
        defer { testScheduler.stopScheduling() }

        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(1200), // 20 minutes from now (enough for 10-minute alert)
        )

        // Schedule with the test preferences
        await testScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

        // Verify we got scheduled alerts
        #expect(
            testScheduler.scheduledAlerts.count >= 1, "Should have at least one scheduled alert",
        )

        let reminderAlerts = testScheduler.scheduledAlerts.filter {
            if case .reminder = $0.alertType { true } else { false }
        }
        #expect(reminderAlerts.count >= 1, "Should have at least one reminder alert")

        let firstAlert = try #require(reminderAlerts.first)

        if case let .reminder(minutes) = firstAlert.alertType {
            #expect(minutes == 10, "EventScheduler should use the specified preference value")
        } else {
            Issue.record("Expected reminder alert type")
        }
    }

    @Test
    func lengthBasedTimingPreferences() async throws {
        defer { eventScheduler.stopScheduling() }
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
        let shortAlert = try #require(eventScheduler.scheduledAlerts.first { $0.event.id == "short" })
        let longAlert = try #require(eventScheduler.scheduledAlerts.first { $0.event.id == "long" })

        // Long events should have different timing than short events
        #expect(shortAlert.triggerDate != longAlert.triggerDate)
    }

    // MARK: - Sound Alert Tests

    @Test
    func soundAlertsWhenEnabled() async {
        defer { eventScheduler.stopScheduling() }
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
        #expect(Set(alerts.map(\.event.id)) == Set([futureEvent.id]))
        #expect(reminderAlerts.map(\.event.id) == [futureEvent.id, futureEvent.id])
    }

    @Test
    func noSoundAlertsWhenDisabled() async {
        defer { eventScheduler.stopScheduling() }
        mockPreferences.testSoundEnabled = false

        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(600),
        )

        await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

        // Should only have overlay alert, no sound alert
        #expect(eventScheduler.scheduledAlerts.map(\.event.id) == [futureEvent.id])
    }

    // MARK: - Snooze Tests

    @Test
    func snoozeScheduling() throws {
        let event = TestUtilities.createTestEvent()

        eventScheduler.scheduleSnooze(for: event, minutes: 5)

        let snoozeAlert = try #require(eventScheduler.scheduledAlerts.first)
        #expect(snoozeAlert.event.id == event.id)
        if case let .snooze(until) = snoozeAlert.alertType {
            let expectedTime = Date().addingTimeInterval(5 * 60)
            let timeDifference = abs(until.timeIntervalSince(expectedTime))
            #expect(timeDifference < 2.0) // Allow 2 second tolerance
        } else {
            Issue.record("Expected snooze alert type")
        }
    }

    @Test
    func snoozePreservedDuringRescheduling() async throws {
        defer { eventScheduler.stopScheduling() }
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
        let scheduler = eventScheduler
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

        #expect(hasSnoozeAlert, "Snooze alert should be preserved during rescheduling")
    }

    // MARK: - Timer Memory Management Tests

    @Test
    func stopSchedulingClearsTimers() async {
        defer { eventScheduler.stopScheduling() }
        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(300),
        )

        await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)
        #expect(eventScheduler.scheduledAlerts.count >= 1)

        eventScheduler.stopScheduling()

        #expect(eventScheduler.scheduledAlerts.isEmpty, "All alerts should be cleared after stop")
    }

    @Test
    func memoryCleanupSimple() async throws {
        // First test if memory leak detection works with a simple object
        class SimpleTestObject {
            var value = 42
        }

        var simpleObject: SimpleTestObject? = SimpleTestObject()
        weak var weakSimple: SimpleTestObject?
        weakSimple = simpleObject
        simpleObject = nil

        #expect(weakSimple == nil, "Simple object should be deallocated")

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

        #expect(weakScheduler == nil, "EventScheduler should be deallocated after cleanup")
    }

    // MARK: - Alert Triggering Tests

    @Test
    func alertTriggering() async {
        let (scheduler, clock) = createClockInjectedScheduler()
        defer { scheduler.stopScheduling() }

        let baseTime = clock.currentTime
        let nearFutureEvent = TestUtilities.createTestEvent(
            startDate: baseTime.addingTimeInterval(120), // 2 minutes from clock's "now"
        )

        // overlayShowMinutesBefore = 1 → alert at baseTime + 120 - 60 = baseTime + 60s.
        // Advance clock to baseTime + 61s so the alert is in the past (missed)
        // but the event hasn't started yet (starts at 120s).
        // scheduleWithoutMonitoring fires missed alerts immediately.
        mockPreferences.testOverlayShowMinutesBefore = 1
        await clock.advance(bySeconds: 61)

        await scheduler.scheduleWithoutMonitoring(
            events: [nearFutureEvent], overlayManager: overlayManager,
        )

        #expect(overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent?.id == nearFutureEvent.id)
    }

    @Test
    func reminderTriggerDoesNotApplyHardcodedFiveMinuteDelay() async {
        let (scheduler, clock) = createClockInjectedScheduler()
        defer { scheduler.stopScheduling() }

        mockPreferences.testOverlayShowMinutesBefore = 6
        mockPreferences.testSoundEnabled = false

        let baseTime = clock.currentTime
        let event = TestUtilities.createTestEvent(
            id: "trigger-no-hardcoded-delay",
            startDate: baseTime.addingTimeInterval(TimeInterval(6 * 60) + 2),
        )

        // Advance clock 3s past baseTime. The overlay trigger is at baseTime + 2s
        // (6 min before event start = 362 - 360 = 2s from baseTime). At clock
        // time baseTime + 3s the trigger is in the past, so scheduleWithoutMonitoring
        // fires it as a missed alert immediately.
        // If a hardcoded 5-minute delay existed instead of honoring the 6-minute
        // preference, the trigger would be at baseTime + 62s (362 - 300), still
        // in the future at baseTime + 3s, and the overlay would NOT fire.
        await clock.advance(bySeconds: 3)
        await scheduler.scheduleWithoutMonitoring(
            events: [event], overlayManager: overlayManager,
        )

        #expect(overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent?.id == event.id)
    }

    // MARK: - Edge Cases

    @Test
    func endedEventsAreSkipped() async {
        defer { eventScheduler.stopScheduling() }
        let endedEvent = TestUtilities.createTestEvent(
            id: "ended",
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-3600),
        )

        await eventScheduler.startScheduling(events: [endedEvent], overlayManager: overlayManager)
        #expect(
            eventScheduler.scheduledAlerts.isEmpty,
            "Events that have already ended should not produce alerts",
        )
    }

    @Test
    func identicalOverlayAndSoundTimingProducesSingleAlert() async {
        defer { eventScheduler.stopScheduling() }
        // When overlay and sound alert timing are the same, only 1 alert should be created
        mockPreferences.testSoundEnabled = true
        mockPreferences.testDefaultAlertMinutes = 5
        mockPreferences.testOverlayShowMinutesBefore = 5

        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(600), // 10 min from now
        )

        await eventScheduler.startScheduling(events: [event], overlayManager: overlayManager)

        // Should have exactly 1 alert, not 2, since timings are identical
        #expect(
            eventScheduler.scheduledAlerts.map(\.event.id) == [event.id],
            "Equal overlay and sound timing should produce 1 alert, not 2",
        )
    }

    @Test
    func allDayEventsWithPastStartAreNotScheduled() async {
        defer { eventScheduler.stopScheduling() }
        let allDay = TestUtilities.createAllDayEvent()

        await eventScheduler.startScheduling(events: [allDay], overlayManager: overlayManager)

        // All-day events that have already started (startDate at beginning of today):
        // - Alert time is in the past
        // - startDate is also in the past
        // The scheduler correctly skips these — they don't qualify as "missed alerts"
        // because the meeting has already started. This prevents surprise overlays
        // for all-day events the user is already aware of.
        #expect(
            eventScheduler.scheduledAlerts.isEmpty,
            "All-day events with past startDate should not produce alerts",
        )
    }

    @Test
    func zeroDurationEventScheduled() async {
        defer { eventScheduler.stopScheduling() }
        let now = Date()
        let zeroDuration = TestUtilities.createTestEvent(
            id: "zero-dur",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(600), // same as start
        )

        await eventScheduler.startScheduling(events: [zeroDuration], overlayManager: overlayManager)

        // Zero duration event is valid (e.g. a reminder) — should still get an alert
        let alerts = eventScheduler.scheduledAlerts
        #expect(alerts.count >= 1, "Zero duration event should produce at least one alert")
        #expect(alerts.first?.event.id == "zero-dur")
    }

    @Test
    func negativeSnoozeMinutesClampedToMinimum() {
        let event = TestUtilities.createTestEvent()
        eventScheduler.scheduleSnooze(for: event, minutes: -5)

        let alerts = eventScheduler.scheduledAlerts
        let snoozeAlert = alerts.first
        #expect(snoozeAlert?.event.id == event.id)

        // Negative minutes should be clamped to 1 minute minimum
        if case let .snooze(until) = snoozeAlert?.alertType {
            let expectedMinimum = Date().addingTimeInterval(60) // 1 minute from now
            let timeDifference = abs(until.timeIntervalSince(expectedMinimum))
            #expect(timeDifference < 2.0, "Negative snooze should be clamped to 1 minute, not \(until)")
        } else {
            Issue.record("Expected snooze alert type")
        }
    }

    @Test
    func zeroSnoozeMinutesClampedToMinimum() {
        let event = TestUtilities.createTestEvent()
        eventScheduler.scheduleSnooze(for: event, minutes: 0)

        let alerts = eventScheduler.scheduledAlerts
        let snoozeAlert = alerts.first
        #expect(snoozeAlert?.event.id == event.id)

        if case let .snooze(until) = snoozeAlert?.alertType {
            let expectedMinimum = Date().addingTimeInterval(60)
            let timeDifference = abs(until.timeIntervalSince(expectedMinimum))
            #expect(timeDifference < 2.0, "Zero snooze should be clamped to 1 minute")
        } else {
            Issue.record("Expected snooze alert type")
        }
    }

    // MARK: - Performance Tests

    @Test
    func largeNumberOfEvents() async {
        defer { eventScheduler.stopScheduling() }
        let numberOfEvents = 100
        let events = (0 ..< numberOfEvents).map { index in
            TestUtilities.createTestEvent(
                id: "event-\(index)",
                startDate: Date()
                    .addingTimeInterval(Double(index * 60 + 300)), // Start 5 minutes from now, spaced 1 minute apart
            )
        }

        let scheduler = eventScheduler
        let overlay = overlayManager
        let (_, schedulingTime) = await TestUtilities.measureTimeAsync { @MainActor @Sendable in
            await scheduler.startScheduling(
                events: events, overlayManager: overlay,
            )
        }

        // Scheduling should complete quickly even with many events
        #expect(schedulingTime < 1.0, "Scheduling 100 events should take less than 1 second")

        // Should have alerts for all future events (may include multiple alert types per event)
        #expect(eventScheduler.scheduledAlerts.count >= numberOfEvents)
    }
}
