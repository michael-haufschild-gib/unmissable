import Foundation
import Testing
@testable import Unmissable

/// E2E tests for keyboard shortcut interaction paths through the full stack.
/// ShortcutsManager.dismissOverlay() and joinMeeting() are private, so these tests
/// exercise the exact same logic path: check overlay state → extract link → act.
/// This verifies the E2E flow that shortcuts execute without requiring Magnet HotKey
/// registration (which needs an app host).
@MainActor
struct ShortcutFlowE2ETests {
    private let env: E2ETestEnvironment
    private let linkParser: LinkParser

    init() async throws {
        env = try await E2ETestEnvironment()
        linkParser = LinkParser()
    }

    // MARK: - Dismiss Shortcut Path

    /// Replicates ShortcutsManager.dismissOverlay():
    /// guard isOverlayVisible → hideOverlay()
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

        // Execute dismiss shortcut logic
        if env.overlayManager.isOverlayVisible {
            env.overlayManager.hideOverlay()
        }

        #expect(!env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent == nil)
    }

    @Test
    func dismissShortcutPath_noOpWhenNoOverlay() {
        // No overlay shown — shortcut should be a no-op
        #expect(!env.overlayManager.isOverlayVisible)

        let shouldDismiss = env.overlayManager.isOverlayVisible
        if shouldDismiss {
            env.overlayManager.hideOverlay()
        }

        #expect(!shouldDismiss, "Dismiss guard should reject when no overlay visible")
        #expect(!env.overlayManager.isOverlayVisible)
    }

    // MARK: - Join Shortcut Path

    /// Replicates ShortcutsManager.joinMeeting():
    /// guard isOverlayVisible, let event = activeEvent,
    ///       let url = linkParser.primaryLink(for: event) → open(url) + hideOverlay()
    @Test
    func joinShortcutPath_extractsLinkAndHidesOverlay() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-shortcut-join",
            title: "Shortcut Join Meeting",
            minutesFromNow: 10,
            provider: .meet,
        )
        try await env.seedAndSchedule([meetEvent])

        // Fetch from DB to get round-tripped event
        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        env.overlayManager.showOverlayImmediately(for: dbEvent)
        #expect(env.overlayManager.isOverlayVisible)

        // Execute join shortcut logic (minus NSWorkspace.open which can't run in SPM)
        var joinURL: URL?
        if env.overlayManager.isOverlayVisible,
           let event = env.overlayManager.activeEvent,
           let url = linkParser.primaryLink(for: event)
        {
            joinURL = url
            env.overlayManager.hideOverlay()
        }

        // Verify join link was correctly extracted
        let url = try #require(joinURL, "Join shortcut should extract a meeting URL")
        #expect(url.host == "meet.google.com")

        // Verify overlay was hidden (as real joinMeeting does after opening URL)
        #expect(!env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent == nil)
    }

    @Test
    func joinShortcutPath_noOpForInPersonMeeting() async throws {
        // In-person event has no meeting link — join shortcut should not act
        let inPersonEvent = E2EEventBuilder.futureEvent(
            id: "e2e-shortcut-nojoin",
            title: "In-Person Meeting",
            minutesFromNow: 10,
        )
        try await env.seedAndSchedule([inPersonEvent])

        env.overlayManager.showOverlayImmediately(for: inPersonEvent)
        #expect(env.overlayManager.isOverlayVisible)

        // Execute join shortcut logic
        var joinAttempted = false
        if env.overlayManager.isOverlayVisible,
           let event = env.overlayManager.activeEvent,
           linkParser.primaryLink(for: event) != nil
        {
            joinAttempted = true
            env.overlayManager.hideOverlay()
        }

        #expect(!joinAttempted, "Join should not trigger for in-person meeting")
        #expect(
            env.overlayManager.isOverlayVisible,
            "Overlay should remain visible when join is not possible",
        )
    }

    @Test
    func joinShortcutPath_noOpWhenNoOverlay() {
        #expect(!env.overlayManager.isOverlayVisible)

        var joinAttempted = false
        if env.overlayManager.isOverlayVisible,
           let event = env.overlayManager.activeEvent,
           linkParser.primaryLink(for: event) != nil
        {
            joinAttempted = true
        }

        #expect(!joinAttempted, "Join should not trigger when no overlay is visible")
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

        // Fetch from DB for round-tripped event
        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try #require(fetched.first)

        // Show overlay, snooze, then simulate re-fire
        env.overlayManager.showOverlayImmediately(for: dbEvent)
        #expect(env.overlayManager.isOverlayVisible)

        env.overlayManager.snoozeOverlay(for: 1)
        #expect(!env.overlayManager.isOverlayVisible)

        // Simulate snooze re-fire
        env.overlayManager.showOverlayImmediately(for: dbEvent, fromSnooze: true)

        // Execute join shortcut logic on the re-fired overlay
        var joinURL: URL?
        if env.overlayManager.isOverlayVisible,
           let event = env.overlayManager.activeEvent,
           let url = linkParser.primaryLink(for: event)
        {
            joinURL = url
            env.overlayManager.hideOverlay()
        }

        let url = try #require(joinURL, "Join should work after snooze re-fire")
        #expect(url.host == "zoom.us")
        #expect(!env.overlayManager.isOverlayVisible)
    }
}
