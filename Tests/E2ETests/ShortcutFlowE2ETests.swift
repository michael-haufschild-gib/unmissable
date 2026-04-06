import Foundation
import Testing
@testable import Unmissable

/// E2E tests for keyboard shortcut interaction paths through the full stack.
/// ShortcutsManager.dismissOverlay() and joinMeeting() are now internal, so these tests
/// call the real methods directly via @testable import, ensuring they stay in sync with
/// production logic without replicating guard conditions.
@MainActor
struct ShortcutFlowE2ETests {
    private let env: E2ETestEnvironment
    private let shortcutsManager: ShortcutsManager

    init() async throws {
        env = try await E2ETestEnvironment()
        // HotKey registration may fail in the test host (no app bundle), but that's
        // fine — we call dismissOverlay()/joinMeeting() directly, not via HotKey.
        shortcutsManager = ShortcutsManager(
            overlayManager: env.overlayManager,
            linkParser: LinkParser(),
        )
    }

    // MARK: - Dismiss Shortcut Path

    @Test
    func dismissShortcutPath_hidesVisibleOverlay() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-shortcut-dismiss",
            title: "Shortcut Dismiss Meeting",
            minutesFromNow: 10,
        )
        try await env.seedAndSchedule([event])

        env.overlayManager.showOverlayImmediately(for: event)
        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent?.id == event.id)

        shortcutsManager.dismissOverlay()

        #expect(!env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent == nil)
    }

    @Test
    func dismissShortcutPath_noOpWhenNoOverlay() {
        #expect(!env.overlayManager.isOverlayVisible)

        shortcutsManager.dismissOverlay()

        #expect(!env.overlayManager.isOverlayVisible)
    }

    // MARK: - Join Shortcut Path

    /// joinMeeting() opens the URL via NSWorkspace (which we can't verify in tests)
    /// and hides the overlay. We verify the overlay is hidden; the URL extraction
    /// is tested separately to confirm the correct link was found.
    @Test
    func joinShortcutPath_hidesOverlayForOnlineMeeting() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-shortcut-join",
            title: "Shortcut Join Meeting",
            minutesFromNow: 10,
            provider: .meet,
        )
        try await env.seedAndSchedule([meetEvent])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        env.overlayManager.showOverlayImmediately(for: dbEvent)
        #expect(env.overlayManager.isOverlayVisible)

        // Verify link is extractable (joinMeeting will use this same path)
        let url = try #require(
            LinkParser().primaryLink(for: dbEvent),
            "Event should have an extractable meeting URL",
        )
        #expect(url.host == "meet.google.com")

        // joinMeeting() calls NSWorkspace.shared.open(url) then hideOverlay().
        // In test environment NSWorkspace.open is a no-op (no app host), but hideOverlay works.
        shortcutsManager.joinMeeting()

        #expect(!env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent == nil)
    }

    @Test
    func joinShortcutPath_noOpForInPersonMeeting() async throws {
        let inPersonEvent = E2EEventBuilder.futureEvent(
            id: "e2e-shortcut-nojoin",
            title: "In-Person Meeting",
            minutesFromNow: 10,
        )
        try await env.seedAndSchedule([inPersonEvent])

        env.overlayManager.showOverlayImmediately(for: inPersonEvent)
        #expect(env.overlayManager.isOverlayVisible)

        // joinMeeting guards on primaryLink — no link means no action, overlay stays
        shortcutsManager.joinMeeting()

        #expect(
            env.overlayManager.isOverlayVisible,
            "Overlay should remain visible when join is not possible",
        )
    }

    @Test
    func joinShortcutPath_noOpWhenNoOverlay() {
        #expect(!env.overlayManager.isOverlayVisible)

        shortcutsManager.joinMeeting()

        #expect(!env.overlayManager.isOverlayVisible)
    }

    // MARK: - Shortcut After Snooze Re-Fire

    @Test
    func joinShortcutPath_worksAfterSnoozeRefire() async throws {
        env.preferencesManager.setOverlayShowMinutesBefore(0)

        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-shortcut-refire",
            title: "Shortcut After Refire",
            minutesFromNow: 1,
            provider: .zoom,
        )
        try await env.seedAndSchedule([meetEvent])

        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        // Show overlay, snooze, then simulate re-fire
        env.overlayManager.showOverlayImmediately(for: dbEvent)
        #expect(env.overlayManager.isOverlayVisible)

        env.overlayManager.snoozeOverlay(for: 1)
        #expect(!env.overlayManager.isOverlayVisible)

        // Simulate snooze re-fire
        env.overlayManager.showOverlayImmediately(for: dbEvent, fromSnooze: true)

        // Verify the link is extractable after re-fire
        let url = try #require(
            LinkParser().primaryLink(for: dbEvent),
            "Event should have an extractable meeting URL after re-fire",
        )
        #expect(url.host == "zoom.us")

        // joinMeeting works on the re-fired overlay
        shortcutsManager.joinMeeting()

        #expect(!env.overlayManager.isOverlayVisible)
    }
}
