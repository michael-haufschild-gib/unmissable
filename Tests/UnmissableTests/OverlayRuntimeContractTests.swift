import Foundation
@testable import Unmissable
import XCTest

@MainActor
final class OverlayRuntimeContractTests: XCTestCase {
    private var overlayManager: TestSafeOverlayManager!

    override func setUp() async throws {
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        try await super.setUp()
    }

    override func tearDown() async throws {
        overlayManager.hideOverlay()
        overlayManager = nil
        try await super.tearDown()
    }

    func testFutureEventIsScheduledWithoutImmediateDisplay() async throws {
        let futureEvent = TestUtilities.createTestEvent(
            id: "runtime-future-schedule",
            startDate: Date().addingTimeInterval(3600)
        )

        overlayManager.showOverlay(for: futureEvent, minutesBeforeMeeting: 5, fromSnooze: false)

        XCTAssertFalse(overlayManager.isOverlayVisible)

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in true }

        XCTAssertFalse(overlayManager.isOverlayVisible)
    }

    func testScheduledOverlayAppearsNearExpectedTriggerTime() async {
        let expectedDelay: TimeInterval = 2
        let leadMinutes = 2
        let scheduledEvent = TestUtilities.createTestEvent(
            id: "runtime-delay-2s",
            startDate: Date().addingTimeInterval(TimeInterval(leadMinutes * 60) + expectedDelay)
        )

        let startTime = Date()
        overlayManager.showOverlay(for: scheduledEvent, minutesBeforeMeeting: leadMinutes, fromSnooze: false)

        let appeared = await waitUntil(timeout: 6.0) {
            self.overlayManager.isOverlayVisible
        }

        XCTAssertTrue(appeared, "Scheduled overlay should appear before timeout")
        let timingError = abs(Date().timeIntervalSince(startTime) - expectedDelay)
        XCTAssertLessThan(timingError, 1.2, "Trigger timing drift should stay under 1.2s")
    }

    func testMultipleScheduledOverlaysCanFireSequentially() async {
        let delays: [TimeInterval] = [1.0, 2.0, 3.0]
        let leadMinutes = 2
        let events = delays.enumerated().map { index, delay in
            TestUtilities.createTestEvent(
                id: "runtime-multi-\(index)",
                startDate: Date().addingTimeInterval(TimeInterval(leadMinutes * 60) + delay)
            )
        }

        for event in events {
            overlayManager.showOverlay(for: event, minutesBeforeMeeting: leadMinutes, fromSnooze: false)
        }

        var triggeredIDs = Set<String>()

        let completed = await waitUntil(timeout: 10.0) {
            if self.overlayManager.isOverlayVisible,
               let activeID = self.overlayManager.activeEvent?.id,
               !triggeredIDs.contains(activeID)
            {
                triggeredIDs.insert(activeID)
                self.overlayManager.hideOverlay()
            }
            return triggeredIDs.count == events.count
        }

        XCTAssertTrue(completed, "All scheduled overlays should eventually fire")
        XCTAssertEqual(triggeredIDs.count, events.count)
    }

    func testHideDoesNotCancelPendingFutureOverlays() async {
        let leadMinutes = 2
        let futureEvent = TestUtilities.createTestEvent(
            id: "runtime-pending-future",
            startDate: Date().addingTimeInterval(TimeInterval(leadMinutes * 60) + 2)
        )
        let immediateEvent = TestUtilities.createTestEvent(
            id: "runtime-immediate",
            startDate: Date().addingTimeInterval(60)
        )

        overlayManager.showOverlay(for: futureEvent, minutesBeforeMeeting: leadMinutes, fromSnooze: false)
        overlayManager.showOverlay(for: immediateEvent, minutesBeforeMeeting: 5, fromSnooze: false)

        XCTAssertTrue(overlayManager.isOverlayVisible)
        overlayManager.hideOverlay()

        let futureTriggered = await waitUntil(timeout: 6.0) {
            self.overlayManager.isOverlayVisible && self.overlayManager.activeEvent?.id == futureEvent.id
        }

        XCTAssertTrue(futureTriggered, "Hiding current overlay should not cancel other pending schedules")
    }

    func testRapidShowHideCycleRemainsResponsive() {
        let immediateEvent = TestUtilities.createTestEvent(
            id: "runtime-rapid-cycle",
            startDate: Date().addingTimeInterval(60)
        )

        let startTime = Date()

        for _ in 0 ..< 25 {
            overlayManager.showOverlay(for: immediateEvent, minutesBeforeMeeting: 5, fromSnooze: false)
            overlayManager.hideOverlay()
        }

        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertLessThan(elapsed, 3.0, "Rapid show/hide cycles should complete quickly")
    }

    func testConcurrentShowHideOperationsRemainConsistent() async {
        let startTime = Date()

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 20 {
                group.addTask { @MainActor in
                    if index % 2 == 0 {
                        let event = TestUtilities.createTestEvent(
                            id: "runtime-concurrent-\(index)",
                            startDate: Date().addingTimeInterval(60)
                        )
                        self.overlayManager.showOverlay(for: event, minutesBeforeMeeting: 5, fromSnooze: false)
                    } else {
                        self.overlayManager.hideOverlay()
                    }
                }
            }
            await group.waitForAll()
        }

        overlayManager.hideOverlay()

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
        XCTAssertLessThan(Date().timeIntervalSince(startTime), 3.0)
    }

    func testEndedEventsAreIgnoredUnlessFromSnooze() {
        let endedEvent = TestUtilities.createTestEvent(
            id: "runtime-ended",
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date().addingTimeInterval(-1800)
        )

        overlayManager.showOverlay(for: endedEvent, minutesBeforeMeeting: 5, fromSnooze: false)

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)

        overlayManager.showOverlay(for: endedEvent, minutesBeforeMeeting: 0, fromSnooze: true)

        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, endedEvent.id)
    }

    func testMalformedEventCanStillBeShownAndSnoozed() {
        let malformedEvent = Event(
            id: "",
            title: "",
            startDate: Date().addingTimeInterval(300),
            endDate: Date().addingTimeInterval(300),
            organizer: "",
            calendarId: "runtime-malformed"
        )

        overlayManager.showOverlay(for: malformedEvent, minutesBeforeMeeting: 5, fromSnooze: false)

        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, malformedEvent.id)

        overlayManager.snoozeOverlay(for: 1)

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    private func waitUntil(
        timeout: TimeInterval,
        pollInterval: Duration = .milliseconds(50),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return true
            }

            // swiftlint:disable:next no_raw_task_sleep_in_tests - polling implementation
            try? await Task.sleep(for: pollInterval)
        }

        return condition()
    }
}
