import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import Unmissable

@MainActor
struct OverlaySnapshotTests {
    // Snapshot tests use `.image` strategy to catch visual regressions:
    // wrong colors, broken layout, clipped text, missing elements.
    // All event dates (including createdAt/updatedAt) are fixed to epoch-based
    // values for determinism — using Date() would make snapshots change every run.
    // Structural regressions (wrong data bindings, missing environment objects)
    // are covered by OverlayContentViewTests and OverlayRuntimeContractTests.

    /// Tolerances for time-dependent text (countdown, meeting time) that varies
    /// between runs. precision = fraction of pixels that must match; 0.95 allows
    /// up to 5% pixel differences, covering the countdown and time display text
    /// while still catching layout, color, and structural regressions.
    private let precision: Float = 0.95
    private let perceptualPrecision: Float = 0.95

    private let snapshotSize = CGSize(width: 1200, height: 800)

    @Test
    func overlayContentBeforeMeeting() {
        let controller = makeHostingController(event: createSampleEvent())
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: snapshotSize),
        )
    }

    @Test
    func overlayContentWithoutMeetingLink() {
        let controller = makeHostingController(event: createSampleEventWithoutLink())
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: snapshotSize),
        )
    }

    @Test
    func overlayContentWithLongTitle() {
        let controller = makeHostingController(event: createSampleEventWithLongTitle())
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: snapshotSize),
        )
    }

    @Test
    func overlayContentFromSnooze() {
        let controller = makeHostingController(event: createSampleEvent(), isFromSnooze: true)
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: snapshotSize),
        )
    }

    // MARK: - Helpers

    private func makeHostingController(
        event: Event,
        isFromSnooze: Bool = false,
    ) -> NSHostingController<some View> {
        let themeManager = ThemeManager()
        let preferencesManager = PreferencesManager(themeManager: themeManager)
        let view = OverlayContentView(
            event: event,
            linkParser: LinkParser(),
            onDismiss: {},
            onJoin: {},
            onSnooze: { _ in },
            isFromSnooze: isFromSnooze,
        )
        .environment(preferencesManager)
        .themed(themeManager: themeManager)
        .frame(width: 1200, height: 800)

        return NSHostingController(rootView: view)
    }

    /// Fixed epoch date for deterministic metadata fields.
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Event start 5 minutes from now. Countdown shows ~"05:00" which is stable
    /// across runs — a few seconds of drift is absorbed by perceptualPrecision.
    private static let meetingOffset: TimeInterval = 300

    private func createSampleEvent() -> Event {
        let start = Date().addingTimeInterval(Self.meetingOffset)
        return Event(
            id: "snapshot-test",
            title: "Important Team Meeting",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            organizer: "john.doe@company.com",
            calendarId: "primary",
            // swiftlint:disable:next force_unwrapping
            links: [URL(string: "https://meet.google.com/abc-defg-hij")!],
            provider: .meet,
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
        )
    }

    private func createSampleEventWithoutLink() -> Event {
        let start = Date().addingTimeInterval(Self.meetingOffset)
        return Event(
            id: "snapshot-test-no-link",
            title: "In-Person Meeting",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            organizer: "jane.smith@company.com",
            calendarId: "primary",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
        )
    }

    private func createSampleEventWithLongTitle() -> Event {
        let start = Date().addingTimeInterval(Self.meetingOffset)
        return Event(
            id: "snapshot-test-long",
            title:
            "Very Important Cross-Functional Strategic Planning Meeting with Multiple Stakeholders",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            organizer: "strategic.planner@company.com",
            calendarId: "primary",
            // swiftlint:disable:next force_unwrapping
            links: [URL(string: "https://meet.google.com/abc-defg-hij")!],
            provider: .meet,
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
        )
    }
}
