import Foundation
import Testing
@testable import Unmissable

/// Tests the OverlayManaging protocol contract via TestSafeOverlayManager.
/// These tests verify the overlay state machine:
/// hidden → show → visible → hide → hidden, and snooze behavior.
@MainActor
struct OverlayRuntimeContractTests {
    private var overlayManager: TestSafeOverlayManager

    init() {
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
    }

    // MARK: - State Machine: Show/Hide

    @Test
    func showOverlaySetsVisibleAndActiveEvent() {
        let event = TestUtilities.createTestEvent(
            id: "contract-show",
        )

        overlayManager.showOverlay(
            for: event,
            fromSnooze: false,
        )

        #expect(overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent?.id == event.id)
    }

    @Test
    func hideOverlayClearsState() {
        let event = TestUtilities.createTestEvent(
            id: "contract-hide",
        )

        overlayManager.showOverlay(
            for: event,
            fromSnooze: false,
        )
        overlayManager.hideOverlay()

        #expect(!overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent == nil)
    }

    @Test
    func showReplacesActiveEvent() {
        let event1 = TestUtilities.createTestEvent(id: "contract-replace-1")
        let event2 = TestUtilities.createTestEvent(id: "contract-replace-2")

        overlayManager.showOverlay(
            for: event1,
            fromSnooze: false,
        )
        overlayManager.showOverlay(
            for: event2,
            fromSnooze: false,
        )

        #expect(overlayManager.isOverlayVisible)
        #expect(
            overlayManager.activeEvent?.id == event2.id,
            "Second show should replace the first event",
        )
    }

    @Test
    func hideOnAlreadyHiddenIsNoOp() {
        overlayManager.hideOverlay()
        overlayManager.hideOverlay()

        #expect(!overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent == nil)
    }

    // MARK: - Snooze

    @Test
    func snoozeHidesOverlayAndClearsActiveEvent() {
        let event = TestUtilities.createTestEvent(
            id: "contract-snooze",
        )

        overlayManager.showOverlay(
            for: event,
            fromSnooze: false,
        )
        overlayManager.snoozeOverlay(for: 5)

        #expect(!overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent == nil)
    }

    @Test
    func snoozeWithNoActiveEventIsNoOp() {
        overlayManager.snoozeOverlay(for: 5)

        #expect(!overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent == nil)
    }

    // MARK: - Stress Tests

    @Test
    func rapidShowHideCycleRemainsResponsive() {
        let event = TestUtilities.createTestEvent(
            id: "contract-rapid-cycle",
        )

        let startTime = Date()

        for _ in 0 ..< 25 {
            overlayManager.showOverlay(
                for: event,
                fromSnooze: false,
            )
            overlayManager.hideOverlay()
        }

        let elapsed = Date().timeIntervalSince(startTime)

        #expect(!overlayManager.isOverlayVisible)
        #expect(
            elapsed < 3.0,
            "Rapid show/hide cycles should complete quickly",
        )
    }

    @Test
    func concurrentShowHideOperationsRemainConsistent() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 20 {
                group.addTask { @MainActor in
                    if index.isMultiple(of: 2) {
                        let event = TestUtilities.createTestEvent(
                            id: "contract-concurrent-\(index)",
                        )
                        self.overlayManager.showOverlay(
                            for: event,
                            fromSnooze: false,
                        )
                    } else {
                        self.overlayManager.hideOverlay()
                    }
                }
            }
            await group.waitForAll()
        }

        overlayManager.hideOverlay()

        #expect(!overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent == nil)
    }

    // MARK: - Edge Cases

    @Test
    func malformedEventCanStillBeShownAndSnoozed() {
        let malformedEvent = Event(
            id: "",
            title: "",
            startDate: Date().addingTimeInterval(300),
            endDate: Date().addingTimeInterval(300),
            organizer: "",
            calendarId: "contract-malformed",
        )

        overlayManager.showOverlay(
            for: malformedEvent,
            fromSnooze: false,
        )

        #expect(overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent?.id == malformedEvent.id)

        overlayManager.snoozeOverlay(for: 1)

        #expect(!overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent == nil)
    }

    @Test
    func timeUntilMeetingReflectsActiveEvent() {
        let futureEvent = TestUtilities.createTestEvent(
            id: "contract-time-until",
            startDate: Date().addingTimeInterval(600),
        )

        #expect(
            overlayManager.timeUntilMeeting == 0,
            "No active event → timeUntilMeeting should be 0",
        )

        overlayManager.showOverlay(
            for: futureEvent,
            fromSnooze: false,
        )

        #expect(
            overlayManager.timeUntilMeeting > 500,
            "Active future event → timeUntilMeeting should be positive",
        )
    }
}
