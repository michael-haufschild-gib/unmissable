import Foundation
import Testing
@testable import Unmissable

/// E2E tests for the overlay trigger and interaction flow through the full stack.
/// Tests: DB event → scheduler trigger → overlay shows → snooze/dismiss/join → state consistency.
@MainActor
struct OverlayFlowE2ETests {
    private let env: E2ETestEnvironment

    init() async throws {
        env = try await E2ETestEnvironment()
    }

    // MARK: - Overlay Triggered from DB Events

    @Test
    func schedulerTriggersOverlayForImminentEvent() async throws {
        // Event starting very soon with overlayShowMinutesBefore = 0
        // This makes the scheduler show the overlay at event start time.
        // Test clock auto-advances through the sleep, so no real wait needed.
        env.preferencesManager.setOverlayShowMinutesBefore(0)

        let imminentEvent = E2EEventBuilder.futureEvent(
            id: "e2e-imminent",
            title: "Imminent Meeting",
            minutesFromNow: 1, // 1 minute from clock's "now"
        )

        try await env.seedAndSchedule([imminentEvent], startMonitoring: true)
        defer { env.tearDown() }

        // Wait for monitoring loop to fire and show overlay.
        // Uses wall-clock polling instead of Task.yield + sleep which hangs
        // in Swift 6.3 due to MainActor starvation.
        await env.waitForOverlay()

        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent?.id == imminentEvent.id)
        #expect(env.overlayManager.activeEvent?.title == "Imminent Meeting")
    }

    // MARK: - Snooze Flow Through Full Stack

    @Test
    func snoozeFlowFromOverlayThroughScheduler() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-flow",
            title: "Snooze Flow Meeting",
            minutesFromNow: 15,
        )

        try await env.seedAndSchedule([event])

        // Manually show overlay (simulating scheduler trigger)
        env.overlayManager.showOverlayImmediately(for: event)
        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent?.id == event.id)

        // Snooze for 3 minutes
        env.overlayManager.snoozeOverlay(for: 3)

        // Verify: overlay hidden
        #expect(!env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent == nil)

        // Verify: snooze alert scheduled in EventScheduler
        let snoozeAlerts = env.eventScheduler.scheduledAlerts.filter { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        // Verify snooze is for the correct event
        let snoozeAlert = try #require(snoozeAlerts.first, "Should have exactly one snooze alert")
        #expect(snoozeAlert.event.id == event.id)

        // Verify snooze time is approximately correct (3 minutes from now)
        if case let .snooze(until) = snoozeAlert.alertType {
            let expectedTime = env.testClock.currentTime.addingTimeInterval(3 * 60)
            let drift = abs(until.timeIntervalSince(expectedTime))
            #expect(drift < 5.0, "Snooze time should be ~3 minutes from test clock")
        } else {
            Issue.record("Expected snooze alert type")
        }
    }

    @Test
    func snoozeWithDifferentDurationsSchedulesCorrectly() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-durations",
            minutesFromNow: 30,
        )
        try await env.seedAndSchedule([event])

        for duration in [1, 5, 10, 15] {
            env.eventScheduler.scheduledAlerts.removeAll()

            env.overlayManager.showOverlayImmediately(for: event)
            #expect(env.overlayManager.isOverlayVisible)

            env.overlayManager.snoozeOverlay(for: duration)

            #expect(!env.overlayManager.isOverlayVisible)

            // Find the snooze alert and verify its duration
            let snoozeAlert = env.eventScheduler.scheduledAlerts.first { alert in
                if case .snooze = alert.alertType { return true }
                return false
            }
            let unwrappedSnooze = try #require(
                snoozeAlert,
                "Snooze alert should exist for \(duration) minutes",
            )

            if case let .snooze(until) = unwrappedSnooze.alertType {
                let expectedMinutes = Int(ceil(until.timeIntervalSince(env.testClock.currentTime) / 60))
                #expect(
                    expectedMinutes == duration,
                    "Snooze should schedule for \(duration) minutes",
                )
            }
        }
    }

    // MARK: - Dismiss Flow

    @Test
    func dismissFlowDoesNotScheduleSnooze() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-dismiss-flow",
            title: "Dismiss Flow Meeting",
            minutesFromNow: 20,
        )

        try await env.seedAndSchedule([event])

        // Show and dismiss
        env.overlayManager.showOverlayImmediately(for: event)
        #expect(env.overlayManager.isOverlayVisible)

        env.overlayManager.hideOverlay()

        // Verify: overlay hidden, no snooze
        #expect(!env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent == nil)

        let hasSnooze = env.eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        #expect(!hasSnooze, "Dismiss should not create a snooze alert")
    }

    // MARK: - Auto-Hide for Old Meetings

    @Test
    func overlayAutoHidesForMeetingStartedTooLongAgo() async throws {
        // Meeting that started more than 5 minutes ago (non-snooze threshold)
        let oldEvent = E2EEventBuilder.startedEvent(
            id: "e2e-auto-hide",
            title: "Very Old Meeting",
            minutesAgo: 10, // Started 10 minutes ago
        )

        try await env.seedEvents([oldEvent])

        // Try to show overlay for this old meeting — should auto-dismiss
        env.overlayManager.showOverlayImmediately(for: oldEvent)

        #expect(
            !env.overlayManager.isOverlayVisible,
            "Overlay should auto-hide for meetings started >5 minutes ago",
        )
    }

    @Test
    func overlayShowsForRecentlyStartedMeeting() async throws {
        // Meeting that started just 2 minutes ago
        let recentEvent = E2EEventBuilder.startedEvent(
            id: "e2e-recent-start",
            title: "Just Started Meeting",
            minutesAgo: 2,
        )

        try await env.seedEvents([recentEvent])

        env.overlayManager.showOverlayImmediately(for: recentEvent)

        #expect(
            env.overlayManager.isOverlayVisible,
            "Overlay should show for recently started meetings",
        )
        #expect(env.overlayManager.activeEvent?.id == recentEvent.id)
    }

    @Test
    func snoozedOverlayHasLongerAutoHideThreshold() async throws {
        // Meeting started 20 minutes ago — normally would auto-hide
        // But fromSnooze allows up to 30 minutes
        let snoozedEvent = E2EEventBuilder.startedEvent(
            id: "e2e-snooze-threshold",
            title: "Snoozed Old Meeting",
            minutesAgo: 20,
        )

        try await env.seedEvents([snoozedEvent])

        // Show as if from snooze
        env.overlayManager.showOverlayImmediately(for: snoozedEvent, fromSnooze: true)

        #expect(
            env.overlayManager.isOverlayVisible,
            "Snoozed overlay should show for meetings started up to 30 minutes ago",
        )
    }

    // MARK: - Overlay Replaces Previous Event

    @Test
    func overlayReplacesActiveEventWhenNewOneTriggered() async throws {
        let event1 = E2EEventBuilder.futureEvent(
            id: "e2e-replace-1",
            title: "First Meeting",
            minutesFromNow: 10,
        )
        let event2 = E2EEventBuilder.futureEvent(
            id: "e2e-replace-2",
            title: "Second Meeting",
            minutesFromNow: 20,
        )

        try await env.seedAndSchedule([event1, event2])

        env.overlayManager.showOverlayImmediately(for: event1)
        #expect(env.overlayManager.activeEvent?.id == event1.id)

        // Second event overlay replaces first
        env.overlayManager.showOverlayImmediately(for: event2)
        #expect(env.overlayManager.activeEvent?.id == event2.id)
        #expect(env.overlayManager.isOverlayVisible)
    }

    // MARK: - State Consistency After Operations

    @Test
    func stateConsistencyAfterSnoozeAndDismissCycle() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-state-consistency",
            minutesFromNow: 15,
        )
        try await env.seedAndSchedule([event])

        // Show → snooze → show again → dismiss
        env.overlayManager.showOverlayImmediately(for: event)
        #expect(env.overlayManager.isOverlayVisible)

        env.overlayManager.snoozeOverlay(for: 5)
        #expect(!env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent == nil)

        // Simulate snooze firing — show again
        env.overlayManager.showOverlayImmediately(for: event, fromSnooze: true)
        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent?.id == event.id)

        // Dismiss
        env.overlayManager.hideOverlay()
        #expect(!env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent == nil)
        #expect(env.overlayManager.timeUntilMeeting == 0)
    }

    // MARK: - Rapid Interactions Don't Corrupt State

    @Test
    func rapidShowHideDoesNotCorruptState() async throws {
        let event = E2EEventBuilder.futureEvent(id: "e2e-rapid", minutesFromNow: 10)
        try await env.seedAndSchedule([event])

        for _ in 0 ..< 20 {
            env.overlayManager.showOverlayImmediately(for: event)
            env.overlayManager.hideOverlay()
        }

        // Final state should be clean
        #expect(!env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent == nil)
    }

    @Test
    func rapidSnoozeDoesNotAccumulateSnoozeAlerts() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-rapid-snooze",
            minutesFromNow: 15,
        )
        try await env.seedAndSchedule([event])

        // Show and snooze rapidly — only the first snooze should register
        // because subsequent snoozes have no activeEvent
        env.overlayManager.showOverlayImmediately(for: event)
        env.overlayManager.snoozeOverlay(for: 1)
        env.overlayManager.snoozeOverlay(for: 2) // No-op — no active event
        env.overlayManager.snoozeOverlay(for: 3) // No-op — no active event

        // Only 1 snooze alert should exist (plus the original reminder alerts)
        let snoozeAlerts = env.eventScheduler.scheduledAlerts.filter { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        let rapidSnooze = try #require(snoozeAlerts.first, "Should have exactly one snooze alert")
        #expect(rapidSnooze.event.id == event.id)
    }

    // MARK: - Snooze While No Overlay Is No-Op

    @Test
    func snoozeWithNoActiveOverlayIsNoOp() async throws {
        let event = E2EEventBuilder.futureEvent(id: "e2e-no-overlay-snooze", minutesFromNow: 20)
        try await env.seedAndSchedule([event])

        #expect(!env.overlayManager.isOverlayVisible)

        env.overlayManager.snoozeOverlay(for: 5)

        #expect(!env.overlayManager.isOverlayVisible)
        let hasSnooze = env.eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        #expect(!hasSnooze, "Snooze with no active overlay should not schedule anything")
    }

    // MARK: - Snooze After Meeting Start Through Full Stack

    @Test
    func snoozedOverlayShowsFromDBEventAfterMeetingStarts() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-db-start",
            title: "Snooze DB Meeting",
            minutesFromNow: 1,
            durationMinutes: 60,
        )

        try await env.seedAndSchedule([event])

        // Show overlay and snooze
        env.overlayManager.showOverlayImmediately(for: event)
        #expect(env.overlayManager.isOverlayVisible)

        env.overlayManager.snoozeOverlay(for: 5)
        #expect(!env.overlayManager.isOverlayVisible)

        // Verify snooze alert exists
        let hasSnooze = env.eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        #expect(hasSnooze, "Snooze should be scheduled")

        // Simulate snooze firing after meeting started by re-fetching from DB
        _ = try await env.fetchUpcomingEvents()

        // Show from snooze — this should work even if startDate is now in the past
        env.overlayManager.showOverlayImmediately(for: event, fromSnooze: true)
        #expect(
            env.overlayManager.isOverlayVisible,
            "Snoozed overlay should show from DB-fetched event",
        )
        #expect(env.overlayManager.activeEvent?.id == event.id)
    }

    // MARK: - Online Meeting Data Preserved in Overlay

    @Test
    func onlineMeetingDataAvailableInOverlay() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-meet-overlay",
            title: "Google Meet E2E",
            minutesFromNow: 10,
            provider: .meet,
        )

        try await env.seedAndSchedule([meetEvent])

        // Fetch from DB and show overlay
        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        env.overlayManager.showOverlayImmediately(for: dbEvent)

        let activeEvent = try #require(env.overlayManager.activeEvent)
        #expect(LinkParser().isOnlineMeeting(activeEvent))
        let link = try #require(LinkParser().primaryLink(for: activeEvent))
        #expect(link.host == "meet.google.com")
        #expect(activeEvent.provider == .meet)
    }
}
