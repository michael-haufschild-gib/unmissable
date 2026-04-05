import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import Unmissable

/// Snapshot tests for the menu bar entry point: both `MenuBarView` (popover content)
/// and `MenuBarLabelView` (status bar label). Covers all user-visible states:
/// disconnected, auth error, connected empty, connected with events, syncing,
/// and database error.
///
/// These tests use `TestMenuBarEnvironment` which wires a test-safe AppState
/// (uses `TestSafeOverlayManager`; no system side effects).
@MainActor
struct MenuBarSnapshotTests {
    /// Tolerance for time-dependent text (event times, countdown).
    /// 0.95 allows up to 5% pixel differences while catching layout/color regressions.
    private let precision: Float = 0.95
    private let perceptualPrecision: Float = 0.95

    private let popoverSize = CGSize(width: 340, height: 500)
    private let labelSize = CGSize(width: 200, height: 22)

    // MARK: - MenuBarView: Disconnected States

    @Test
    func menuBarView_disconnected() {
        let env = TestMenuBarEnvironment()
        env.calendarService.isConnected = false
        env.calendarService.authError = nil

        let controller = env.hostMenuBarView(size: popoverSize)
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: popoverSize),
        )
    }

    @Test
    func menuBarView_disconnectedWithAuthError() {
        let env = TestMenuBarEnvironment()
        env.calendarService.isConnected = false
        env.calendarService.authError = "Missing OAuth configuration. Check Config.plist."

        let controller = env.hostMenuBarView(size: popoverSize)
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: popoverSize),
        )
    }

    // MARK: - MenuBarView: Connected States

    @Test
    func menuBarView_connectedNoEvents() {
        let env = TestMenuBarEnvironment()
        env.calendarService.isConnected = true
        env.calendarService.events = []
        env.calendarService.syncStatus = .idle

        let controller = env.hostMenuBarView(size: popoverSize)
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: popoverSize),
        )
    }

    @Test
    func menuBarView_connectedWithEvents() throws {
        let env = TestMenuBarEnvironment()
        env.calendarService.isConnected = true
        env.calendarService.syncStatus = .idle
        env.calendarService.events = try [
            createEvent(title: "Team Standup", minutesFromNow: 10),
            createEvent(title: "1:1 with Manager", minutesFromNow: 60),
            createEvent(
                title: "Sprint Planning",
                minutesFromNow: 120,
                links: [
                    #require(URL(string: "https://meet.google.com/abc-defg-hij")),
                ],
                provider: .meet,
            ),
        ]

        let controller = env.hostMenuBarView(size: popoverSize)
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: popoverSize),
        )
    }

    @Test
    func menuBarView_connectedSyncing() {
        let env = TestMenuBarEnvironment()
        env.calendarService.isConnected = true
        env.calendarService.syncStatus = .syncing
        env.calendarService.events = [
            createEvent(title: "Team Meeting", minutesFromNow: 15),
        ]

        let controller = env.hostMenuBarView(size: popoverSize)
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: popoverSize),
        )
    }

    // MARK: - MenuBarView: Error States

    @Test
    func menuBarView_databaseError() {
        let env = TestMenuBarEnvironment()
        env.appState.databaseError = "Failed to open database: disk I/O error"
        env.calendarService.isConnected = true
        env.calendarService.events = []
        env.calendarService.syncStatus = .idle

        let controller = env.hostMenuBarView(size: popoverSize)
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: popoverSize),
        )
    }

    // MARK: - MenuBarLabelView: Display Modes

    @Test
    func menuBarLabelView_iconMode() {
        let env = TestMenuBarEnvironment()
        env.preferencesManager.setMenuBarDisplayMode(.icon)
        env.menuBarPreviewManager.updateEvents([
            createEvent(minutesFromNow: 30),
        ])

        let controller = env.hostMenuBarLabelView(size: labelSize)
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: labelSize),
        )
    }

    // Timer and nameTimer label snapshots use live countdown text that changes each run.
    // The visual layout is covered by menuBarView_connectedWithEvents.
    // Here we verify the label logic: correct text format and icon suppression.

    @Test
    func menuBarLabelView_timerMode() {
        let env = TestMenuBarEnvironment()
        env.preferencesManager.setMenuBarDisplayMode(.timer)
        env.menuBarPreviewManager.updateEvents([
            createEvent(minutesFromNow: 25),
        ])

        #expect(!env.menuBarPreviewManager.shouldShowIcon)
        let text = env.menuBarPreviewManager.menuBarText
        #expect(text != nil)
        #expect(text?.contains("min") == true, "Timer label should contain 'min', got: \(text ?? "nil")")
    }

    @Test
    func menuBarLabelView_nameTimerMode() {
        let env = TestMenuBarEnvironment()
        env.preferencesManager.setMenuBarDisplayMode(.nameTimer)
        env.menuBarPreviewManager.updateEvents([
            createEvent(title: "Design Review", minutesFromNow: 8),
        ])

        #expect(!env.menuBarPreviewManager.shouldShowIcon)
        let text = env.menuBarPreviewManager.menuBarText
        #expect(text != nil)
        // "Design Review" (13 chars) exceeds maxMeetingNameLength (12) → truncated to "Design Re..."
        #expect(
            text?.contains("Design Re") == true,
            "Name-timer label should contain truncated name prefix, got: \(text ?? "nil")",
        )
        #expect(text?.contains("min") == true, "Name-timer label should contain 'min', got: \(text ?? "nil")")
    }

    // MARK: - Event Helpers

    private static let secondsPerMinute: TimeInterval = 60

    private func createEvent(
        title: String = "Test Meeting",
        minutesFromNow: Int = 15,
        durationMinutes: Int = 60,
        links: [URL] = [],
        provider: Provider? = nil,
    ) -> Event {
        let start = Date().addingTimeInterval(TimeInterval(minutesFromNow) * Self.secondsPerMinute)
        let end = start.addingTimeInterval(TimeInterval(durationMinutes) * Self.secondsPerMinute)
        return Event(
            id: "snap-\(UUID().uuidString)",
            title: title,
            startDate: start,
            endDate: end,
            calendarId: "snapshot-cal",
            links: links,
            provider: provider,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
    }
}
