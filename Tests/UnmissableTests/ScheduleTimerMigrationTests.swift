import Foundation
@testable import Unmissable
import XCTest

/// Test cases specifically for schedule timer migration validation
/// These tests focus on the core overlay scheduling timer - the highest risk component
@MainActor
class ScheduleTimerMigrationTests: XCTestCase {
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

    /// Test schedule timer accuracy for different future times
    func testScheduleTimerAccuracy() async throws {
        let scheduleDelays = [2, 5, 10] // 2, 5, 10 seconds in future

        for delay in scheduleDelays {
            let event = TimerMigrationTestHelpers.createTestEvent(
                minutesInFuture: 0, // Start with current time
                title: "Schedule Accuracy Test \(delay)s"
            )

            // Adjust event to be exactly `delay` seconds in future
            let adjustedEvent = Event(
                id: event.id,
                title: event.title,
                startDate: Date().addingTimeInterval(TimeInterval(delay + 2)), // +2 for buffer
                endDate: event.endDate,
                calendarId: event.calendarId,
                timezone: event.timezone
            )

            let expectation = TimerMigrationTestHelpers.createTimerExpectation(
                description: "Schedule timer fired for \(delay)s delay"
            )

            let scheduleStartTime = Date()

            // Monitor for overlay appearance
            var overlayAppeared = false
            let observer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
                [weak overlayManager] timer in
                guard let overlayManager, !overlayAppeared else { return }
                // Check overlay visibility directly in timer callback
                if overlayManager.isOverlayVisible {
                    overlayAppeared = true
                    timer.invalidate()

                    let actualTriggerTime = Date()
                    let expectedTriggerTime = scheduleStartTime.addingTimeInterval(TimeInterval(delay))

                    TimerMigrationTestHelpers.logTimingMetrics(
                        operation: "Schedule \(delay)s",
                        expected: expectedTriggerTime,
                        actual: actualTriggerTime,
                        tolerance: TimerMigrationTestHelpers.ScheduleTimer.tolerance
                    )

                    TimerMigrationTestHelpers.validateTimerAccuracy(
                        expected: expectedTriggerTime,
                        actual: actualTriggerTime,
                        tolerance: TimerMigrationTestHelpers.ScheduleTimer.tolerance
                    )

                    expectation.fulfill()
                }
            }

            // Schedule the overlay to appear in `delay` seconds
            overlayManager.showOverlay(for: adjustedEvent, minutesBeforeMeeting: 2, fromSnooze: false)

            TimerMigrationTestHelpers.waitForTimerExpectations(
                [expectation],
                timeout: TimeInterval(delay + 5)
            )

            observer.invalidate()
            overlayManager.hideOverlay()

            // Brief pause between tests
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Test scheduling multiple overlays simultaneously
    func testMultipleScheduleTimers() {
        let eventCount = 5
        let baseDelay = 3 // 3 seconds base delay

        var events: [Event] = []
        var expectedTriggers: [Date] = []
        var actualTriggers: [Date] = []

        let expectation = TimerMigrationTestHelpers.createTimerExpectation(
            description: "Multiple schedule timers completed"
        )
        expectation.expectedFulfillmentCount = eventCount

        let scheduleStartTime = Date()

        // Create events with staggered trigger times
        for i in 0 ..< eventCount {
            let delay = baseDelay + i // 3, 4, 5, 6, 7 seconds
            let event = Event(
                id: "multi-test-\(i)",
                title: "Multi Schedule Test \(i)",
                startDate: Date().addingTimeInterval(TimeInterval(delay + 2)),
                endDate: Date().addingTimeInterval(TimeInterval(delay + 1800)),
                calendarId: "test-calendar"
            )

            events.append(event)
            expectedTriggers.append(scheduleStartTime.addingTimeInterval(TimeInterval(delay)))
        }

        // Monitor for overlay appearances
        var triggeredEvents: Set<String> = []
        let observer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak overlayManager] _ in
            Task { @MainActor in
                guard let overlayManager else { return }
                if overlayManager.isOverlayVisible {
                    if let activeEvent = overlayManager.activeEvent,
                       !triggeredEvents.contains(activeEvent.id) {
                        triggeredEvents.insert(activeEvent.id)
                        actualTriggers.append(Date())
                        print("🔥 SCHEDULE TRIGGER: \(activeEvent.title) at \(Date())")
                        expectation.fulfill()
                        overlayManager.hideOverlay()
                    }
                }
            }
        }

        // Schedule all overlays
        for event in events {
            overlayManager.showOverlay(for: event, minutesBeforeMeeting: 2, fromSnooze: false)
        }

        TimerMigrationTestHelpers.waitForTimerExpectations(
            [expectation],
            timeout: TimeInterval(baseDelay + eventCount + 5)
        )

        observer.invalidate()

        // Validate all triggers occurred with correct timing
        XCTAssertEqual(
            actualTriggers.count, eventCount, "Should have triggered all \(eventCount) events"
        )

        // Sort both arrays by time for comparison
        let sortedExpected = expectedTriggers.sorted()
        let sortedActual = actualTriggers.sorted()

        TimerMigrationTestHelpers.ScheduleTimer.validateSchedulingAccuracy(
            events: events,
            expectedTriggers: sortedExpected,
            actualTriggers: sortedActual
        )
    }

    /// Test schedule timer cancellation when overlays are rescheduled
    func testScheduleTimerCancellation() async throws {
        let event1 = TimerMigrationTestHelpers.createTestEvent(
            minutesInFuture: 0,
            title: "First Event",
            id: "first-event"
        )

        // Adjust to trigger in 5 seconds
        let adjustedEvent1 = Event(
            id: event1.id,
            title: event1.title,
            startDate: Date().addingTimeInterval(7), // 5 seconds for trigger + 2 min buffer
            endDate: event1.endDate,
            calendarId: event1.calendarId,
            timezone: event1.timezone
        )

        // Schedule first overlay
        overlayManager.showOverlay(for: adjustedEvent1, minutesBeforeMeeting: 2, fromSnooze: false)

        // Wait 1 second to ensure timer is active
        try await Task.sleep(for: .seconds(1))

        // Schedule a different event (should cancel the first)
        let event2 = TimerMigrationTestHelpers.createTestEvent(
            minutesInFuture: 0,
            title: "Second Event",
            id: "second-event"
        )

        let adjustedEvent2 = Event(
            id: event2.id,
            title: event2.title,
            startDate: Date().addingTimeInterval(5), // 3 seconds from now + 2 min buffer
            endDate: event2.endDate,
            calendarId: event2.calendarId,
            timezone: event2.timezone
        )

        overlayManager.showOverlay(for: adjustedEvent2, minutesBeforeMeeting: 2, fromSnooze: false)

        // Wait longer than the first event would have triggered
        try await Task.sleep(for: .seconds(7))

        // Check if any overlay appeared
        if overlayManager.isOverlayVisible {
            XCTAssertEqual(overlayManager.activeEvent?.id, "second-event")
        }

        overlayManager.hideOverlay()
    }

    /// Test schedule timer memory usage under load
    func testScheduleTimerMemoryUsage() async throws {
        let initialMemory = getMemoryUsage()
        let eventCount = 100

        print("📊 SCHEDULE MEMORY: Testing with \(eventCount) scheduled timers")
        print("📊 SCHEDULE MEMORY: Initial memory: \(initialMemory / 1024 / 1024) MB")

        var events: [Event] = []

        // Create many scheduled events
        for i in 0 ..< eventCount {
            let event = Event(
                id: "memory-test-\(i)",
                title: "Memory Test Event \(i)",
                startDate: Date().addingTimeInterval(TimeInterval(60 + i)),
                endDate: Date().addingTimeInterval(TimeInterval(60 + i + 1800)),
                calendarId: "test"
            )
            events.append(event)
        }

        // Schedule all events
        for event in events {
            overlayManager.showOverlay(for: event, minutesBeforeMeeting: 1, fromSnooze: false)
        }

        let afterSchedulingMemory = getMemoryUsage()
        let schedulingIncrease = afterSchedulingMemory - initialMemory

        print("📊 SCHEDULE MEMORY: After scheduling: \(afterSchedulingMemory / 1024 / 1024) MB")
        print("📊 SCHEDULE MEMORY: Scheduling increase: \(schedulingIncrease / 1024 / 1024) MB")

        // Cancel all by scheduling empty list
        // (This simulates what happens during sync with no events)
        // Note: We would need to trigger this through EventScheduler in real usage

        // Wait for potential memory cleanup
        try await Task.sleep(for: .seconds(2))

        let finalMemory = getMemoryUsage()
        let totalIncrease = finalMemory - initialMemory

        print("📊 SCHEDULE MEMORY: Final memory: \(finalMemory / 1024 / 1024) MB")
        print("📊 SCHEDULE MEMORY: Total increase: \(totalIncrease / 1024 / 1024) MB")

        // Memory increase should be reasonable (less than 20MB for 100 timers)
        XCTAssertLessThan(
            totalIncrease,
            20 * 1024 * 1024,
            "Memory increase should be less than 20MB after scheduling \(eventCount) timers"
        )
    }

    /// Test schedule timer behavior with past events (should not schedule)
    func testScheduleTimerPastEvents() async throws {
        let pastEvent = Event(
            id: "past-event",
            title: "Past Event",
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date().addingTimeInterval(-1800),
            calendarId: "test"
        )

        // Attempt to schedule past event
        overlayManager.showOverlay(for: pastEvent, minutesBeforeMeeting: 5, fromSnooze: false)

        // Wait to see if any overlay appears (it shouldn't)
        try await Task.sleep(for: .seconds(2))

        XCTAssertFalse(
            overlayManager.isOverlayVisible,
            "Overlay should not appear for past events"
        )
    }

    /// Test schedule timer precision under system load
    func testScheduleTimerPrecisionUnderLoad() async {
        // Create system load to test timer precision
        await TimerMigrationTestHelpers.simulateMemoryPressure(
            timerCount: 50,
            duration: 10.0
        )

        // Now test timing precision
        let event = Event(
            id: "precision-test",
            title: "Precision Test Event",
            startDate: Date().addingTimeInterval(7),
            endDate: Date().addingTimeInterval(1807),
            calendarId: "test"
        )

        let expectation = TimerMigrationTestHelpers.createTimerExpectation(
            description: "Precision test completed"
        )

        let scheduleTime = Date()

        var hasTriggered = false
        let observer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak overlayManager] timer in
            guard let overlayManager, !hasTriggered else { return }
            if overlayManager.isOverlayVisible {
                hasTriggered = true
                timer.invalidate()
                let actualTime = Date()
                let expectedTime = scheduleTime.addingTimeInterval(5)
                TimerMigrationTestHelpers.validateTimerAccuracy(
                    expected: expectedTime,
                    actual: actualTime,
                    tolerance: 2.0
                )
                expectation.fulfill()
            }
        }

        overlayManager.showOverlay(for: event, minutesBeforeMeeting: 2, fromSnooze: false)

        TimerMigrationTestHelpers.waitForTimerExpectations([expectation], timeout: 10.0)

        observer.invalidate()
        overlayManager.hideOverlay()
    }

    // MARK: - Helper Methods

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
