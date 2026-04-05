import Foundation
import Testing
@testable import Unmissable

/// E2E tests for focus mode (DND) interaction with overlay behavior.
/// Tests: DND state → shouldShowOverlay → overlay suppression/override.
@MainActor
struct FocusModeE2ETests {
    private let env: E2ETestEnvironment
    private let focusModeManager: FocusModeManager

    init() async throws {
        env = try await E2ETestEnvironment()
        focusModeManager = FocusModeManager(
            preferencesManager: env.preferencesManager,
            isTestMode: true,
        )
    }

    // MARK: - DND Off: Overlay Always Shows

    @Test
    func overlayShowsWhenDNDIsOff() async throws {
        focusModeManager.isDoNotDisturbEnabled = false
        env.preferencesManager.setOverrideFocusMode(false)

        #expect(
            focusModeManager.shouldShowOverlay(),
            "Overlay should show when DND is off",
        )
        #expect(
            focusModeManager.shouldPlaySound(),
            "Sound should play when DND is off",
        )

        // Verify through full stack
        let event = E2EEventBuilder.futureEvent(id: "e2e-dnd-off", minutesFromNow: 10)
        try await env.seedAndSchedule([event])

        env.overlayManager.showOverlayImmediately(for: event)
        #expect(env.overlayManager.isOverlayVisible)
    }

    // MARK: - DND On Without Override: Overlay Suppressed

    @Test
    func overlaySuppressedWhenDNDOnAndOverrideDisabled() {
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(false)

        #expect(
            !focusModeManager.shouldShowOverlay(),
            "Overlay should be suppressed when DND is on and override is disabled",
        )
        #expect(
            !focusModeManager.shouldPlaySound(),
            "Sound should be suppressed when DND is on and override is disabled",
        )
    }

    // MARK: - DND On With Override: Overlay Shows

    @Test
    func overlayShowsWhenDNDOnAndOverrideEnabled() {
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(true)

        #expect(
            focusModeManager.shouldShowOverlay(),
            "Overlay should show when DND is on but override is enabled",
        )
        #expect(
            focusModeManager.shouldPlaySound(),
            "Sound should play when DND is on but override is enabled",
        )
    }

    // MARK: - Toggle DND During Active State

    @Test
    func togglingDNDChangesOverlayDecision() {
        env.preferencesManager.setOverrideFocusMode(false)

        // Start with DND off
        focusModeManager.isDoNotDisturbEnabled = false
        #expect(focusModeManager.shouldShowOverlay())

        // Enable DND
        focusModeManager.isDoNotDisturbEnabled = true
        #expect(!focusModeManager.shouldShowOverlay())

        // Disable DND again
        focusModeManager.isDoNotDisturbEnabled = false
        #expect(focusModeManager.shouldShowOverlay())
    }

    @Test
    func togglingOverridePreferenceChangesDecision() {
        focusModeManager.isDoNotDisturbEnabled = true

        // Override disabled — suppressed
        env.preferencesManager.setOverrideFocusMode(false)
        #expect(!focusModeManager.shouldShowOverlay())

        // Enable override — shows
        env.preferencesManager.setOverrideFocusMode(true)
        #expect(focusModeManager.shouldShowOverlay())

        // Disable override again — suppressed
        env.preferencesManager.setOverrideFocusMode(false)
        #expect(!focusModeManager.shouldShowOverlay())
    }

    // MARK: - FocusMode Integration with Full Stack

    @Test
    func focusModeDecisionUsedBeforeOverlayShow() async throws {
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(false)

        let event = E2EEventBuilder.futureEvent(id: "e2e-focus-gate", minutesFromNow: 10)
        try await env.seedAndSchedule([event])

        // Check focus mode BEFORE showing overlay (production behavior)
        let shouldShow = focusModeManager.shouldShowOverlay()
        if shouldShow {
            env.overlayManager.showOverlayImmediately(for: event)
        }

        #expect(!shouldShow)
        #expect(!env.overlayManager.isOverlayVisible)

        // Now enable override — overlay should be showable
        env.preferencesManager.setOverrideFocusMode(true)
        let shouldShowNow = focusModeManager.shouldShowOverlay()
        if shouldShowNow {
            env.overlayManager.showOverlayImmediately(for: event)
        }

        #expect(shouldShowNow)
        #expect(env.overlayManager.isOverlayVisible)
    }

    // MARK: - Focus Mode + Scheduler Overlay Interaction

    @Test
    func focusModeGateWithSchedulerOverlayTrigger() async throws {
        // Start with DND on, override disabled
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(false)
        env.preferencesManager.setOverlayShowMinutesBefore(0)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-focus-scheduler",
            title: "Focus Gate Meeting",
            minutesFromNow: 1,
        )

        try await env.seedAndSchedule([event])

        // Verify DND suppresses the overlay decision
        #expect(
            !focusModeManager.shouldShowOverlay(),
            "DND on + override disabled should suppress overlay",
        )

        // Now enable override
        env.preferencesManager.setOverrideFocusMode(true)
        #expect(
            focusModeManager.shouldShowOverlay(),
            "DND on + override enabled should allow overlay",
        )

        // Manually trigger overlay (as scheduler would after focus check passes)
        env.overlayManager.showOverlayImmediately(for: event)
        #expect(env.overlayManager.isOverlayVisible)
    }

    // MARK: - Sound Follows Overlay Logic

    @Test
    func soundFollowsSameLogicAsOverlay() {
        // DND off
        focusModeManager.isDoNotDisturbEnabled = false
        #expect(
            focusModeManager.shouldShowOverlay() == focusModeManager.shouldPlaySound(),
            "Sound and overlay decisions should match when DND is off",
        )

        // DND on, no override
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(false)
        #expect(
            focusModeManager.shouldShowOverlay() == focusModeManager.shouldPlaySound(),
            "Sound and overlay decisions should match when DND is on without override",
        )

        // DND on, with override
        env.preferencesManager.setOverrideFocusMode(true)
        #expect(
            focusModeManager.shouldShowOverlay() == focusModeManager.shouldPlaySound(),
            "Sound and overlay decisions should match when DND is on with override",
        )
    }
}
