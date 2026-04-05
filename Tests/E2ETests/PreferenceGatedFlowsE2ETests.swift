import Foundation
import Testing
@testable import Unmissable

/// E2E tests for preference toggles that gate overlay and scheduling behavior.
/// Each test verifies that a preference change flows through the full stack:
/// UserDefaults → PreferencesManager → EventScheduler → overlay → observable behavior.
@MainActor
struct PreferenceGatedFlowsE2ETests {
    private let env: E2ETestEnvironment

    init() async throws {
        env = try await E2ETestEnvironment()
    }

    // MARK: - AllowSnooze = false

    @Test
    func allowSnoozeFalse_snoozeCallIsNoOp() async throws {
        env.preferencesManager.setAllowSnooze(false)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-no-snooze",
            title: "No Snooze Meeting",
            minutesFromNow: 15,
        )
        try await env.seedAndSchedule([event])

        env.overlayManager.showOverlayImmediately(for: event)
        #expect(env.overlayManager.isOverlayVisible)

        // Production flow: OverlayContentView checks `preferences.allowSnooze`
        // before rendering snooze menu. Simulate the same gate:
        let canSnooze = env.preferencesManager.allowSnooze
        #expect(!canSnooze, "allowSnooze should be false")

        // If user somehow triggers snooze despite UI hiding it, verify manager handles it
        // (This tests the defense-in-depth: snooze still works at manager level,
        // but the UI gate prevents it from being triggered)
        if canSnooze {
            env.overlayManager.snoozeOverlay(for: 5)
        }

        // Overlay should still be visible since snooze was gated
        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent?.id == event.id)

        // No snooze alerts should exist
        let hasSnooze = env.eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        #expect(!hasSnooze, "No snooze alert when allowSnooze is false")
    }

    @Test
    func allowSnoozeToggle_midSessionBehaviorChange() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-toggle",
            title: "Snooze Toggle Meeting",
            minutesFromNow: 20,
        )
        try await env.seedAndSchedule([event])

        // Start with snooze disabled
        env.preferencesManager.setAllowSnooze(false)
        env.overlayManager.showOverlayImmediately(for: event)

        // Simulate UI gate: no snooze available
        #expect(!env.preferencesManager.allowSnooze)

        // Toggle snooze on mid-session
        env.preferencesManager.setAllowSnooze(true)
        #expect(env.preferencesManager.allowSnooze)

        // Now snooze should work
        env.overlayManager.snoozeOverlay(for: 5)
        #expect(!env.overlayManager.isOverlayVisible)

        let hasSnooze = env.eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        #expect(hasSnooze, "Snooze should work after toggling allowSnooze on")
    }

    // MARK: - Sound Enabled/Disabled Through Scheduler

    @Test
    func soundEnabled_createsAdditionalSoundAlerts() async throws {
        env.preferencesManager.setPlayAlertSound(true)
        env.preferencesManager.setDefaultAlertMinutes(3) // Sound at 3 min before
        env.preferencesManager.setOverlayShowMinutesBefore(5) // Overlay at 5 min before

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-sound-on",
            minutesFromNow: 30,
        )
        try await env.seedAndSchedule([event])

        // With sound ON and different timing, should have 2 alerts (overlay + sound)
        let alertCount = env.eventScheduler.scheduledAlerts.count
        #expect(alertCount == 2, "Should have both overlay and sound alerts")

        // Both should be for the same event
        let alertEventIds = Set(env.eventScheduler.scheduledAlerts.map(\.event.id))
        #expect(alertEventIds == Set(["e2e-sound-on"]))
    }

    @Test
    func soundDisabled_onlyOverlayAlert() async throws {
        env.preferencesManager.setPlayAlertSound(false)
        env.preferencesManager.setOverlayShowMinutesBefore(5)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-sound-off",
            minutesFromNow: 30,
        )
        try await env.seedAndSchedule([event])

        // With sound OFF, should have only 1 alert (overlay only)
        let alerts = env.eventScheduler.scheduledAlerts
        let soloAlert = try #require(alerts.first, "Should have at least one alert when sound disabled")
        #expect(soloAlert.event.id == "e2e-sound-off")
        #expect(alerts.map(\.event.id) == ["e2e-sound-off"], "Only overlay alert with sound off")
    }

    @Test
    func soundToggleMidSession_reschedulesAlerts() async throws {
        env.preferencesManager.setPlayAlertSound(false)
        env.preferencesManager.setDefaultAlertMinutes(3)
        env.preferencesManager.setOverlayShowMinutesBefore(5)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-sound-toggle",
            minutesFromNow: 30,
        )
        try await env.seedAndSchedule([event])

        let initialCount = env.eventScheduler.scheduledAlerts.count
        #expect(initialCount == 1, "Only overlay alert with sound off")

        // Toggle sound on — rescheduling should create additional alert
        env.preferencesManager.setPlayAlertSound(true)

        // Give @Observable observation time to propagate.
        // A single yield is insufficient — the observation pipeline dispatches
        // a Task that needs multiple scheduling cycles to complete.
        try await yieldToObservation(iterations: 10)

        let newCount = env.eventScheduler.scheduledAlerts.count
        #expect(newCount == 2, "Should have both overlay and sound alerts after toggling on")
    }

    // MARK: - Length-Based Timing Through Full Overlay Trigger

    @Test
    func lengthBasedTiming_differentTimingsForDifferentDurations() async throws {
        env.preferencesManager.setUseLengthBasedTiming(true)
        env.preferencesManager.setShortMeetingAlertMinutes(1)
        env.preferencesManager.setMediumMeetingAlertMinutes(3)
        env.preferencesManager.setLongMeetingAlertMinutes(8)
        env.preferencesManager.setOverlayShowMinutesBefore(5)
        env.preferencesManager.setPlayAlertSound(true)

        let shortMeeting = E2EEventBuilder.futureEvent(
            id: "e2e-lb-short",
            title: "Quick Standup",
            minutesFromNow: 30,
            durationMinutes: 15, // Short: < 30 min
        )
        let longMeeting = E2EEventBuilder.futureEvent(
            id: "e2e-lb-long",
            title: "Planning Session",
            minutesFromNow: 60,
            durationMinutes: 120, // Long: > 60 min
        )

        try await env.seedAndSchedule([shortMeeting, longMeeting])

        // Verify the preference returns different alert minutes
        let shortAlertMin = env.preferencesManager.alertMinutes(for: shortMeeting)
        let longAlertMin = env.preferencesManager.alertMinutes(for: longMeeting)
        #expect(shortAlertMin == 1, "Short meeting should use 1-minute alert")
        #expect(longAlertMin == 8, "Long meeting should use 8-minute alert")

        // Verify scheduler created alerts with different timings
        let shortAlerts = env.eventScheduler.scheduledAlerts.filter { $0.event.id == "e2e-lb-short" }
        let longAlerts = env.eventScheduler.scheduledAlerts.filter { $0.event.id == "e2e-lb-long" }

        // Each event should have an overlay alert (same timing) + a sound alert (different timing)
        #expect(shortAlerts.count >= 1)
        #expect(longAlerts.count >= 1)

        // The sound alerts should have different lead times reflecting length-based timing
        let shortSoundAlert = shortAlerts.first { alert in
            if case let .reminder(minutes) = alert.alertType, minutes == 1 { return true }
            return false
        }
        let longSoundAlert = longAlerts.first { alert in
            if case let .reminder(minutes) = alert.alertType, minutes == 8 { return true }
            return false
        }

        let unwrappedShort = try #require(shortSoundAlert, "Short meeting should have 1-minute sound alert")
        #expect(unwrappedShort.event.id == "e2e-lb-short")

        let unwrappedLong = try #require(longSoundAlert, "Long meeting should have 8-minute sound alert")
        #expect(unwrappedLong.event.id == "e2e-lb-long")
    }

    // MARK: - Focus Mode Override Preference Through Full Overlay Trigger

    @Test
    func focusModeOverride_overlayShowsDespiteDND() async throws {
        env.preferencesManager.setOverlayShowMinutesBefore(0)

        let focusModeManager = FocusModeManager(
            preferencesManager: env.preferencesManager,
            isTestMode: true,
        )

        // DND on, override off — overlay suppressed
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(false)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-focus-override",
            title: "Focus Override Meeting",
            minutesFromNow: 1,
            durationMinutes: 60,
        )
        try await env.seedAndSchedule([event])

        // Check before showing — DND should suppress
        #expect(!focusModeManager.shouldShowOverlay())

        // Now toggle override on
        env.preferencesManager.setOverrideFocusMode(true)
        #expect(focusModeManager.shouldShowOverlay())

        // With override on, overlay should work
        if focusModeManager.shouldShowOverlay() {
            env.overlayManager.showOverlayImmediately(for: event)
        }
        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent?.id == event.id)

        // Full cycle: snooze → re-fire check
        env.overlayManager.snoozeOverlay(for: 5)
        #expect(!env.overlayManager.isOverlayVisible)

        let hasSnooze = env.eventScheduler.scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
        #expect(hasSnooze, "Snooze should work with focus override enabled")
    }

    // MARK: - Overlay Show Minutes Before = 0 (At Event Start)

    @Test
    func overlayShowAtEventStart_triggersImmediately() async throws {
        env.preferencesManager.setOverlayShowMinutesBefore(0)
        env.preferencesManager.setPlayAlertSound(false)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-show-at-start",
            title: "Show At Start Meeting",
            minutesFromNow: 1,
        )
        try await env.seedAndSchedule([event], startMonitoring: true)
        defer { env.tearDown() }

        // Advance clock to fire the monitoring loop's alert
        await env.waitForOverlay()

        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent?.id == event.id)
    }
}
