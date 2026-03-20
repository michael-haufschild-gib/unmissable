import Foundation
@testable import Unmissable
import XCTest

/// Tests the OverlayManaging protocol contract via TestSafeOverlayManager.
/// These tests verify the overlay state machine:
/// hidden → show → visible → hide → hidden, and snooze behavior.
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

    // MARK: - State Machine: Show/Hide

    func testShowOverlaySetsVisibleAndActiveEvent() {
        let event = TestUtilities.createTestEvent(
            id: "contract-show"
        )

        overlayManager.showOverlay(
            for: event,
            minutesBeforeMeeting: 5,
            fromSnooze: false
        )

        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, event.id)
    }

    func testHideOverlayClearsState() {
        let event = TestUtilities.createTestEvent(
            id: "contract-hide"
        )

        overlayManager.showOverlay(
            for: event,
            minutesBeforeMeeting: 5,
            fromSnooze: false
        )
        overlayManager.hideOverlay()

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    func testShowReplacesActiveEvent() {
        let event1 = TestUtilities.createTestEvent(id: "contract-replace-1")
        let event2 = TestUtilities.createTestEvent(id: "contract-replace-2")

        overlayManager.showOverlay(
            for: event1,
            minutesBeforeMeeting: 5,
            fromSnooze: false
        )
        overlayManager.showOverlay(
            for: event2,
            minutesBeforeMeeting: 5,
            fromSnooze: false
        )

        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(
            overlayManager.activeEvent?.id,
            event2.id,
            "Second show should replace the first event"
        )
    }

    func testHideOnAlreadyHiddenIsNoOp() {
        overlayManager.hideOverlay()
        overlayManager.hideOverlay()

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    // MARK: - Snooze

    func testSnoozeHidesOverlayAndClearsActiveEvent() {
        let event = TestUtilities.createTestEvent(
            id: "contract-snooze"
        )

        overlayManager.showOverlay(
            for: event,
            minutesBeforeMeeting: 5,
            fromSnooze: false
        )
        overlayManager.snoozeOverlay(for: 5)

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    func testSnoozeWithNoActiveEventIsNoOp() {
        overlayManager.snoozeOverlay(for: 5)

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    // MARK: - Stress Tests

    func testRapidShowHideCycleRemainsResponsive() {
        let event = TestUtilities.createTestEvent(
            id: "contract-rapid-cycle"
        )

        let startTime = Date()

        for _ in 0 ..< 25 {
            overlayManager.showOverlay(
                for: event,
                minutesBeforeMeeting: 5,
                fromSnooze: false
            )
            overlayManager.hideOverlay()
        }

        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertLessThan(
            elapsed, 3.0,
            "Rapid show/hide cycles should complete quickly"
        )
    }

    func testConcurrentShowHideOperationsRemainConsistent() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 20 {
                group.addTask { @MainActor in
                    if index % 2 == 0 {
                        let event = TestUtilities.createTestEvent(
                            id: "contract-concurrent-\(index)"
                        )
                        self.overlayManager.showOverlay(
                            for: event,
                            minutesBeforeMeeting: 5,
                            fromSnooze: false
                        )
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
    }

    // MARK: - Edge Cases

    func testMalformedEventCanStillBeShownAndSnoozed() {
        let malformedEvent = Event(
            id: "",
            title: "",
            startDate: Date().addingTimeInterval(300),
            endDate: Date().addingTimeInterval(300),
            organizer: "",
            calendarId: "contract-malformed"
        )

        overlayManager.showOverlay(
            for: malformedEvent,
            minutesBeforeMeeting: 5,
            fromSnooze: false
        )

        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, malformedEvent.id)

        overlayManager.snoozeOverlay(for: 1)

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(overlayManager.activeEvent)
    }

    func testTimeUntilMeetingReflectsActiveEvent() {
        let futureEvent = TestUtilities.createTestEvent(
            id: "contract-time-until",
            startDate: Date().addingTimeInterval(600)
        )

        XCTAssertEqual(
            overlayManager.timeUntilMeeting,
            0,
            "No active event → timeUntilMeeting should be 0"
        )

        overlayManager.showOverlay(
            for: futureEvent,
            minutesBeforeMeeting: 5,
            fromSnooze: false
        )

        XCTAssertGreaterThan(
            overlayManager.timeUntilMeeting,
            500,
            "Active future event → timeUntilMeeting should be positive"
        )
    }
}
