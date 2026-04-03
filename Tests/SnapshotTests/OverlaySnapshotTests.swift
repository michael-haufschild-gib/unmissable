import AppKit
import SnapshotTesting
import SwiftUI
@testable import Unmissable
import XCTest

@MainActor
final class OverlaySnapshotTests: XCTestCase {
    // Snapshot tests use `.image` strategy to catch visual regressions:
    // wrong colors, broken layout, clipped text, missing elements.
    // All event dates (including createdAt/updatedAt) are fixed to epoch-based
    // values for determinism — using Date() would make snapshots change every run.
    // Structural regressions (wrong data bindings, missing environment objects)
    // are covered by OverlayContentViewTests and OverlayRuntimeContractTests.

    /// Tolerance for minor font rendering differences across macOS versions.
    private let precision: Float = 1.0
    private let perceptualPrecision: Float = 0.98

    private let snapshotSize = CGSize(width: 1200, height: 800)

    func testOverlayContentBeforeMeeting() {
        let controller = makeHostingController(event: createSampleEvent())
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: snapshotSize),
        )
    }

    func testOverlayContentWithoutMeetingLink() {
        let controller = makeHostingController(event: createSampleEventWithoutLink())
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: snapshotSize),
        )
    }

    func testOverlayContentWithLongTitle() {
        let controller = makeHostingController(event: createSampleEventWithLongTitle())
        assertSnapshot(
            of: controller,
            as: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: snapshotSize),
        )
    }

    func testOverlayContentFromSnooze() {
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
        .environmentObject(preferencesManager)
        .themed(themeManager: themeManager)
        .frame(width: 1200, height: 800)

        return NSHostingController(rootView: view)
    }

    /// Fixed epoch date for deterministic snapshot output.
    /// All event metadata uses this to avoid Date()-dependent snapshot drift.
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func createSampleEvent() -> Event {
        Event(
            id: "snapshot-test",
            title: "Important Team Meeting",
            startDate: Date(timeIntervalSince1970: 2_000_000_000),
            endDate: Date(timeIntervalSince1970: 2_000_001_800),
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
        Event(
            id: "snapshot-test-no-link",
            title: "In-Person Meeting",
            startDate: Date(timeIntervalSince1970: 2_000_000_000),
            endDate: Date(timeIntervalSince1970: 2_000_001_800),
            organizer: "jane.smith@company.com",
            calendarId: "primary",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
        )
    }

    private func createSampleEventWithLongTitle() -> Event {
        Event(
            id: "snapshot-test-long",
            title:
            "Very Important Cross-Functional Strategic Planning Meeting with Multiple Stakeholders",
            startDate: Date(timeIntervalSince1970: 2_000_000_000),
            endDate: Date(timeIntervalSince1970: 2_000_001_800),
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
