import Foundation
import TestSupport
@testable import Unmissable
import XCTest

/// E2E tests for keyboard shortcut interaction paths through the full stack.
/// ShortcutsManager.dismissOverlay() and joinMeeting() are private, so these tests
/// exercise the exact same logic path: check overlay state → extract link → act.
/// This verifies the E2E flow that shortcuts execute without requiring Magnet HotKey
/// registration (which needs an app host).
@MainActor
final class ShortcutFlowE2ETests: XCTestCase {
    private var env: E2ETestEnvironment!
    private var linkParser: LinkParser!

    override func setUp() async throws {
        try await super.setUp()
        env = try await E2ETestEnvironment()
        linkParser = LinkParser()
    }

    override func tearDown() async throws {
        env.tearDown()
        linkParser = nil
        env = nil
        try await super.tearDown()
    }

    // MARK: - Dismiss Shortcut Path

    /// Replicates ShortcutsManager.dismissOverlay():
    /// guard isOverlayVisible → hideOverlay()
    func testDismissShortcutPath_hidesVisibleOverlay() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-shortcut-dismiss",
            title: "Shortcut Dismiss Meeting",
            minutesFromNow: 10,
        )
        try await env.seedAndSchedule([event])

        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)

        // Execute dismiss shortcut logic
        if env.overlayManager.isOverlayVisible {
            env.overlayManager.hideOverlay()
        }

        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)
    }

    func testDismissShortcutPath_noOpWhenNoOverlay() {
        // No overlay shown — shortcut should be a no-op
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        let shouldDismiss = env.overlayManager.isOverlayVisible
        if shouldDismiss {
            env.overlayManager.hideOverlay()
        }

        XCTAssertFalse(shouldDismiss, "Dismiss guard should reject when no overlay visible")
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
    }

    // MARK: - Join Shortcut Path

    /// Replicates ShortcutsManager.joinMeeting():
    /// guard isOverlayVisible, let event = activeEvent,
    ///       let url = linkParser.primaryLink(for: event) → open(url) + hideOverlay()
    func testJoinShortcutPath_extractsLinkAndHidesOverlay() async throws {
        let meetEvent = E2EEventBuilder.onlineMeeting(
            id: "e2e-shortcut-join",
            title: "Shortcut Join Meeting",
            minutesFromNow: 10,
            provider: .meet,
        )
        try await env.seedAndSchedule([meetEvent])

        // Fetch from DB to get round-tripped event
        let fetched = try await env.fetchUpcomingEvents()
        let dbEvent = try XCTUnwrap(fetched.first)

        env.overlayManager.showOverlayImmediately(for: dbEvent)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

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
        let url = try XCTUnwrap(joinURL, "Join shortcut should extract a meeting URL")
        XCTAssertEqual(url.host, "meet.google.com")

        // Verify overlay was hidden (as real joinMeeting does after opening URL)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
        XCTAssertNil(env.overlayManager.activeEvent)
    }

    func testJoinShortcutPath_noOpForInPersonMeeting() async throws {
        // In-person event has no meeting link — join shortcut should not act
        let inPersonEvent = E2EEventBuilder.futureEvent(
            id: "e2e-shortcut-nojoin",
            title: "In-Person Meeting",
            minutesFromNow: 10,
        )
        try await env.seedAndSchedule([inPersonEvent])

        env.overlayManager.showOverlayImmediately(for: inPersonEvent)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        // Execute join shortcut logic
        var joinAttempted = false
        if env.overlayManager.isOverlayVisible,
           let event = env.overlayManager.activeEvent,
           linkParser.primaryLink(for: event) != nil
        {
            joinAttempted = true
            env.overlayManager.hideOverlay()
        }

        XCTAssertFalse(joinAttempted, "Join should not trigger for in-person meeting")
        XCTAssertTrue(
            env.overlayManager.isOverlayVisible,
            "Overlay should remain visible when join is not possible",
        )
    }

    func testJoinShortcutPath_noOpWhenNoOverlay() {
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

        var joinAttempted = false
        if env.overlayManager.isOverlayVisible,
           let event = env.overlayManager.activeEvent,
           linkParser.primaryLink(for: event) != nil
        {
            joinAttempted = true
        }

        XCTAssertFalse(joinAttempted, "Join should not trigger when no overlay is visible")
    }

    // MARK: - Shortcut After Snooze Re-Fire

    func testJoinShortcutPath_worksAfterSnoozeRefire() async throws {
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
        let dbEvent = try XCTUnwrap(fetched.first)

        // Show overlay, snooze, then simulate re-fire
        env.overlayManager.showOverlayImmediately(for: dbEvent)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        env.overlayManager.snoozeOverlay(for: 1)
        XCTAssertFalse(env.overlayManager.isOverlayVisible)

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

        let url = try XCTUnwrap(joinURL, "Join should work after snooze re-fire")
        XCTAssertEqual(url.host, "zoom.us")
        XCTAssertFalse(env.overlayManager.isOverlayVisible)
    }
}
