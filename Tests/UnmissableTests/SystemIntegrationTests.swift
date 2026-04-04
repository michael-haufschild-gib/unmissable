import Combine
import TestSupport
@testable import Unmissable
import XCTest

@MainActor
final class SystemIntegrationTests: XCTestCase {
    private var mockPreferences: PreferencesManager!
    private var eventScheduler: EventScheduler!
    private var overlayManager: TestSafeOverlayManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()

        mockPreferences = TestUtilities.createTestPreferencesManager()
        mockPreferences.testSoundEnabled = false // Disable sound to simplify alert counting
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        eventScheduler = EventScheduler(preferencesManager: mockPreferences, linkParser: LinkParser())
        cancellables = Set<AnyCancellable>()

        // Connect the components
        overlayManager.setEventScheduler(eventScheduler)
    }

    override func tearDown() async throws {
        eventScheduler.stopScheduling()
        overlayManager.hideOverlay()
        cancellables.removeAll()

        eventScheduler = nil
        overlayManager = nil
        mockPreferences = nil

        try await super.tearDown()
    }

    // MARK: - End-to-End Event Flow Tests

    func testCompleteEventSchedulingFlow() async throws {
        let futureEvent = TestUtilities.createTestEvent(
            title: "Integration Test Meeting",
            startDate: Date().addingTimeInterval(600), // 10 minutes from now
        )

        // Set preferences for quick testing
        mockPreferences.testOverlayShowMinutesBefore = 9 // 9 minutes before

        // Start the scheduling system
        await eventScheduler.startScheduling(events: [futureEvent], overlayManager: overlayManager)

        // Verify alert was scheduled
        XCTAssertEqual(eventScheduler.scheduledAlerts.map(\.event.id), [futureEvent.id])
        let alert = try XCTUnwrap(eventScheduler.scheduledAlerts.first)
        XCTAssertEqual(alert.event.id, futureEvent.id)

        if case let .reminder(minutes) = alert.alertType {
            XCTAssertEqual(minutes, 9)
        } else {
            XCTFail("Expected reminder alert type")
        }
    }

    func testEventSchedulingWithPreferenceChanges() async throws {
        // Disable sound alerts to isolate overlay scheduling verification
        mockPreferences.testSoundEnabled = false

        let events = [
            TestUtilities.createTestEvent(
                id: "event1",
                startDate: Date().addingTimeInterval(900), // 15 minutes from now
            ),
            TestUtilities.createTestEvent(
                id: "event2",
                startDate: Date().addingTimeInterval(1800), // 30 minutes from now
            ),
        ]

        await eventScheduler.startScheduling(events: events, overlayManager: overlayManager)

        let initialAlertCount = eventScheduler.scheduledAlerts.count
        XCTAssertEqual(initialAlertCount, 2)

        // Change preferences
        mockPreferences.testOverlayShowMinutesBefore = 10

        // Wait for rescheduling to complete
        let scheduler = try XCTUnwrap(eventScheduler)
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            // Check if any alert has the new timing to confirm rescheduling happened
            return scheduler.scheduledAlerts.contains { alert in
                if case let .reminder(minutes) = alert.alertType {
                    return minutes == 10
                }
                return false
            }
        }

        // Verify alerts were rescheduled with new timing
        let updatedAlerts = eventScheduler.scheduledAlerts
        for alert in updatedAlerts {
            if case let .reminder(minutes) = alert.alertType {
                XCTAssertEqual(minutes, 10)
            }
        }
    }

    func testSnoozeWorkflow() async throws {
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(300), // 5 minutes from now
        )

        await eventScheduler.startScheduling(events: [event], overlayManager: overlayManager)

        // Simulate overlay being shown
        overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(overlayManager.isOverlayVisible)

        // Snooze the overlay
        overlayManager.snoozeOverlay(for: 2) // 2 minutes

        // Overlay should be hidden
        XCTAssertFalse(overlayManager.isOverlayVisible)

        // Check that snooze alert was scheduled
        let snoozeAlerts = eventScheduler.scheduledAlerts.filter { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }

        XCTAssertEqual(snoozeAlerts.map(\.event.id), [event.id])

        if case let .snooze(until) = try XCTUnwrap(snoozeAlerts.first?.alertType) {
            let expectedTime = Date().addingTimeInterval(2 * 60)
            let timeDifference = abs(until.timeIntervalSince(expectedTime))
            XCTAssertLessThan(timeDifference, 5.0) // Allow 5 second tolerance
        }
    }

    func testOverlayShowAndHideIntegration() {
        let event = TestUtilities.createTestEvent()

        overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, event.id)

        overlayManager.hideOverlay()
        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    // MARK: - Multi-Event Coordination Tests

    func testMultipleEventsScheduling() async {
        let events = (0 ..< 5).map { index in
            TestUtilities.createTestEvent(
                id: "multi-event-\(index)",
                title: "Meeting \(index)",
                startDate: Date().addingTimeInterval(Double((index + 1) * 300)), // Spaced 5 minutes apart
            )
        }

        await eventScheduler.startScheduling(events: events, overlayManager: overlayManager)

        // Should have scheduled alerts for all events
        let alerts = eventScheduler.scheduledAlerts
        let alertEventIds = alerts.map(\.event.id)
        XCTAssertEqual(alertEventIds, (0 ..< 5).map { "multi-event-\($0)" })

        // Alerts should be sorted by trigger time
        let triggerTimes = alerts.map(\.triggerDate)
        let sortedTimes = triggerTimes.sorted()
        XCTAssertEqual(triggerTimes, sortedTimes)
    }

    func testOverlappingEventsHandling() async {
        let baseTime = Date().addingTimeInterval(600) // 10 minutes from now

        let overlappingEvents = [
            TestUtilities.createTestEvent(
                id: "overlap1",
                startDate: baseTime,
                endDate: baseTime.addingTimeInterval(3600), // 1 hour duration
            ),
            TestUtilities.createTestEvent(
                id: "overlap2",
                startDate: baseTime.addingTimeInterval(1800), // Starts 30 min into first event
                endDate: baseTime.addingTimeInterval(5400), // 90 min duration
            ),
        ]

        await eventScheduler.startScheduling(events: overlappingEvents, overlayManager: overlayManager)

        // Both events should be scheduled
        let alertEventIds = Set(eventScheduler.scheduledAlerts.map(\.event.id))
        XCTAssertEqual(alertEventIds, Set(["overlap1", "overlap2"]))

        // Test that overlays can be shown for overlapping events
        overlayManager.showOverlay(for: overlappingEvents[0])
        XCTAssertEqual(overlayManager.activeEvent?.id, "overlap1")

        overlayManager.showOverlay(for: overlappingEvents[1])
        XCTAssertEqual(overlayManager.activeEvent?.id, "overlap2") // Should replace first overlay
    }

    // MARK: - Error Recovery Tests

    func testSystemRecoveryAfterError() async {
        let validEvent = TestUtilities.createTestEvent(id: "valid")

        await eventScheduler.startScheduling(events: [validEvent], overlayManager: overlayManager)
        XCTAssertEqual(eventScheduler.scheduledAlerts.map(\.event.id), ["valid"])

        // Simulate error by stopping and restarting
        eventScheduler.stopScheduling()
        XCTAssertEqual(eventScheduler.scheduledAlerts, [], "Should have no alerts after stop")

        // System should recover by restarting scheduling
        await eventScheduler.startScheduling(events: [validEvent], overlayManager: overlayManager)
        XCTAssertEqual(eventScheduler.scheduledAlerts.map(\.event.id), ["valid"])
    }

    func testMemoryPressureHandling() async throws {
        // Test with a large number of events to simulate memory pressure
        let largeEventCount = 200
        let events = (0 ..< largeEventCount).map { index in
            TestUtilities.createTestEvent(
                id: "memory-test-\(index)",
                startDate: Date().addingTimeInterval(Double(index * 60 + 600)), // Start 10 min from now, 1 min apart
            )
        }

        let scheduler = try XCTUnwrap(eventScheduler)
        let overlay = try XCTUnwrap(overlayManager)
        let (_, schedulingTime) = await TestUtilities.measureTimeAsync { @MainActor @Sendable in
            await scheduler.startScheduling(events: events, overlayManager: overlay)
        }

        XCTAssertLessThan(
            schedulingTime, 5.0, "Scheduling 200 events should complete in under 5 seconds",
        )
        let alerts = eventScheduler.scheduledAlerts
        XCTAssertEqual(alerts.map(\.event.id).prefix(1), ["memory-test-0"])
        XCTAssertGreaterThanOrEqual(alerts.count, largeEventCount, "Should schedule all events")

        // Test that the system remains responsive
        let testEvent = TestUtilities.createTestEvent(id: "responsiveness-test")
        overlayManager.showOverlayImmediately(for: testEvent)
        XCTAssertTrue(overlayManager.isOverlayVisible)

        overlayManager.hideOverlay()
        XCTAssertFalse(overlayManager.isOverlayVisible)
    }

    // MARK: - State Consistency Tests

    func testStateConsistencyAcrossComponents() async {
        let event = TestUtilities.createTestEvent()

        // Initial state
        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertEqual(eventScheduler.scheduledAlerts, [], "Should start with no alerts")

        // Start scheduling
        await eventScheduler.startScheduling(events: [event], overlayManager: overlayManager)

        // EventScheduler should have alerts
        XCTAssertGreaterThanOrEqual(eventScheduler.scheduledAlerts.count, 1)

        // Show overlay
        overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, event.id)

        // Snooze overlay
        overlayManager.snoozeOverlay(for: 1)
        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)

        // EventScheduler should have snooze alert
        let hasSnoozeAlert = eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        XCTAssertTrue(hasSnoozeAlert)
    }

    func testConcurrentOperations() async {
        let events = (0 ..< 10).map { index in
            TestUtilities.createTestEvent(
                id: "concurrent-\(index)",
                startDate: Date().addingTimeInterval(Double(index * 120 + 600)), // 2 minutes apart
            )
        }

        // Run operations sequentially — all are MainActor-isolated
        await eventScheduler.startScheduling(
            events: events, overlayManager: overlayManager,
        )
        overlayManager.showOverlay(for: events[0])
        mockPreferences.testOverlayShowMinutesBefore = 8

        // System should be in a consistent state
        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertGreaterThanOrEqual(eventScheduler.scheduledAlerts.count, 1)
    }

    // MARK: - Performance Integration Tests

    func testEndToEndPerformance() async throws {
        let eventCount = 50
        let events = (0 ..< eventCount).map { index in
            TestUtilities.createTestEvent(
                id: "perf-\(index)",
                startDate: Date().addingTimeInterval(Double(index * 300 + 600)), // 5 minutes apart
            )
        }

        let scheduler = try XCTUnwrap(eventScheduler)
        let overlay = try XCTUnwrap(overlayManager)
        let prefs = try XCTUnwrap(mockPreferences)
        let (_, totalTime) = await TestUtilities.measureTimeAsync { @MainActor @Sendable in
            // Full end-to-end workflow
            await scheduler.startScheduling(events: events, overlayManager: overlay)

            // Show and hide overlays for first few events
            for event in events.prefix(5) {
                overlay.showOverlayImmediately(for: event)
                overlay.hideOverlay()
            }

            // Change preferences (should trigger rescheduling)
            prefs.testOverlayShowMinutesBefore = 7

            // Wait for rescheduling
            try? await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in true }
        }

        XCTAssertLessThan(totalTime, 10.0, "End-to-end workflow should complete in under 10 seconds")
    }

    // MARK: - Data Flow Tests

    func testPreferenceChangePropagation() async throws {
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(1800), // 30 minutes from now
        )

        // Set initial preferences
        mockPreferences.testOverlayShowMinutesBefore = 5
        mockPreferences.testSoundEnabled = false

        await eventScheduler.startScheduling(events: [event], overlayManager: overlayManager)

        // Only overlay alert, no sound
        XCTAssertEqual(eventScheduler.scheduledAlerts.map(\.event.id), [event.id])

        // Enable sound alerts
        mockPreferences.testSoundEnabled = true
        mockPreferences.testDefaultAlertMinutes = 3

        // Wait for preference change to propagate
        let scheduler = try XCTUnwrap(eventScheduler)
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            return scheduler.scheduledAlerts.count >= 1
        }

        // Should now have different alert configuration
        let updatedAlerts = eventScheduler.scheduledAlerts
        XCTAssertGreaterThanOrEqual(updatedAlerts.count, 1)
    }
}
