import Foundation
@testable import Unmissable
import XCTest

/// E2E tests for focus mode (DND) interaction with overlay behavior.
/// Tests: DND state → shouldShowOverlay → overlay suppression/override.
@MainActor
final class FocusModeE2ETests: XCTestCase {
    private var env: E2ETestEnvironment!
    private var focusModeManager: FocusModeManager!

    override func setUp() async throws {
        try await super.setUp()
        env = try await E2ETestEnvironment()
        focusModeManager = FocusModeManager(
            preferencesManager: env.preferencesManager,
            isTestMode: true,
        )
    }

    override func tearDown() async throws {
        env.tearDown()
        focusModeManager = nil
        env = nil
        try await super.tearDown()
    }

    // MARK: - DND Off: Overlay Always Shows

    func testOverlayShowsWhenDNDIsOff() async throws {
        focusModeManager.isDoNotDisturbEnabled = false
        env.preferencesManager.setOverrideFocusMode(false)

        XCTAssertTrue(
            focusModeManager.shouldShowOverlay(),
            "Overlay should show when DND is off",
        )
        XCTAssertTrue(
            focusModeManager.shouldPlaySound(),
            "Sound should play when DND is off",
        )

        // Verify through full stack
        let event = E2EEventBuilder.futureEvent(id: "e2e-dnd-off", minutesFromNow: 10)
        try await env.seedAndSchedule([event])

        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
    }

    // MARK: - DND On Without Override: Overlay Suppressed

    func testOverlaySuppressedWhenDNDOnAndOverrideDisabled() {
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(false)

        XCTAssertFalse(
            focusModeManager.shouldShowOverlay(),
            "Overlay should be suppressed when DND is on and override is disabled",
        )
        XCTAssertFalse(
            focusModeManager.shouldPlaySound(),
            "Sound should be suppressed when DND is on and override is disabled",
        )
    }

    // MARK: - DND On With Override: Overlay Shows

    func testOverlayShowsWhenDNDOnAndOverrideEnabled() {
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(true)

        XCTAssertTrue(
            focusModeManager.shouldShowOverlay(),
            "Overlay should show when DND is on but override is enabled",
        )
        XCTAssertTrue(
            focusModeManager.shouldPlaySound(),
            "Sound should play when DND is on but override is enabled",
        )
    }

    // MARK: - Toggle DND During Active State

    func testTogglingDNDChangesOverlayDecision() {
        env.preferencesManager.setOverrideFocusMode(false)

        // Start with DND off
        focusModeManager.isDoNotDisturbEnabled = false
        XCTAssertTrue(focusModeManager.shouldShowOverlay())

        // Enable DND
        focusModeManager.isDoNotDisturbEnabled = true
        XCTAssertFalse(focusModeManager.shouldShowOverlay())

        // Disable DND again
        focusModeManager.isDoNotDisturbEnabled = false
        XCTAssertTrue(focusModeManager.shouldShowOverlay())
    }

    func testTogglingOverridePreferenceChangesDecision() {
        focusModeManager.isDoNotDisturbEnabled = true

        // Override disabled — suppressed
        env.preferencesManager.setOverrideFocusMode(false)
        XCTAssertFalse(focusModeManager.shouldShowOverlay())

        // Enable override — shows
        env.preferencesManager.setOverrideFocusMode(true)
        XCTAssertTrue(focusModeManager.shouldShowOverlay())

        // Disable override again — suppressed
        env.preferencesManager.setOverrideFocusMode(false)
        XCTAssertFalse(focusModeManager.shouldShowOverlay())
    }

    // MARK: - FocusMode Integration with Full Stack

    func testFocusModeDecisionUsedBeforeOverlayShow() async throws {
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(false)

        let event = E2EEventBuilder.futureEvent(id: "e2e-focus-gate", minutesFromNow: 10)
        try await env.seedAndSchedule([event])

        // Check focus mode BEFORE showing overlay (production behavior)
        let shouldShow = focusModeManager.shouldShowOverlay()
        if shouldShow {
            env.overlayManager.showOverlayImmediately(for: event)
        }

        XCTAssertFalse(shouldShow)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        // Now enable override — overlay should be showable
        env.preferencesManager.setOverrideFocusMode(true)
        let shouldShowNow = focusModeManager.shouldShowOverlay()
        if shouldShowNow {
            env.overlayManager.showOverlayImmediately(for: event)
        }

        XCTAssertTrue(shouldShowNow)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
    }

    // MARK: - Focus Mode + Scheduler Overlay Interaction

    func testFocusModeGateWithSchedulerOverlayTrigger() async throws {
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
        XCTAssertFalse(
            focusModeManager.shouldShowOverlay(),
            "DND on + override disabled should suppress overlay",
        )

        // Now enable override
        env.preferencesManager.setOverrideFocusMode(true)
        XCTAssertTrue(
            focusModeManager.shouldShowOverlay(),
            "DND on + override enabled should allow overlay",
        )

        // Manually trigger overlay (as scheduler would after focus check passes)
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
    }

    // MARK: - Sound Follows Overlay Logic

    func testSoundFollowsSameLogicAsOverlay() {
        // DND off
        focusModeManager.isDoNotDisturbEnabled = false
        XCTAssertEqual(
            focusModeManager.shouldShowOverlay(),
            focusModeManager.shouldPlaySound(),
            "Sound and overlay decisions should match when DND is off",
        )

        // DND on, no override
        focusModeManager.isDoNotDisturbEnabled = true
        env.preferencesManager.setOverrideFocusMode(false)
        XCTAssertEqual(
            focusModeManager.shouldShowOverlay(),
            focusModeManager.shouldPlaySound(),
            "Sound and overlay decisions should match when DND is on without override",
        )

        // DND on, with override
        env.preferencesManager.setOverrideFocusMode(true)
        XCTAssertEqual(
            focusModeManager.shouldShowOverlay(),
            focusModeManager.shouldPlaySound(),
            "Sound and overlay decisions should match when DND is on with override",
        )
    }
}
