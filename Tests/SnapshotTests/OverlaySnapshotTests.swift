import SnapshotTesting
import SwiftUI
@testable import Unmissable
import XCTest

@MainActor
final class OverlaySnapshotTests: XCTestCase {
    // Snapshot tests use `.dump` strategy to capture the full SwiftUI view tree
    // including text content and modifier chains. This catches meaningful UI regressions
    // (missing text, wrong modifiers, structural changes) unlike `.recursiveDescription`
    // which only shows the NSHostingView shell.
    //
    // To record new baselines: set `isRecording = true` below and run once.
    // Then set it back to `false` for CI.

    override func invokeTest() {
        // Set `isRecording = true` to regenerate reference snapshots
        // isRecording = true
        super.invokeTest()
    }

    func testOverlayContentBeforeMeeting() {
        let view = makeOverlayView(event: createSampleEvent())
        assertSnapshot(of: view, as: .dump)
    }

    func testOverlayContentWithoutMeetingLink() {
        let view = makeOverlayView(event: createSampleEventWithoutLink())
        assertSnapshot(of: view, as: .dump)
    }

    func testOverlayContentWithLongTitle() {
        let view = makeOverlayView(event: createSampleEventWithLongTitle())
        assertSnapshot(of: view, as: .dump)
    }

    func testOverlayContentFromSnooze() {
        let view = makeOverlayView(event: createSampleEvent(), isFromSnooze: true)
        assertSnapshot(of: view, as: .dump)
    }

    // MARK: - Helpers

    private func makeOverlayView(event: Event, isFromSnooze: Bool = false) -> some View {
        let themeManager = ThemeManager()
        let preferencesManager = PreferencesManager(themeManager: themeManager)
        return OverlayContentView(
            event: event,
            linkParser: LinkParser(),
            onDismiss: {},
            onJoin: {},
            onSnooze: { _ in },
            isFromSnooze: isFromSnooze
        )
        .environmentObject(preferencesManager)
        .customThemedEnvironment(themeManager: themeManager)
        .frame(width: 1200, height: 800)
    }

    private func createSampleEvent() -> Event {
        Event(
            id: "snapshot-test",
            title: "Important Team Meeting",
            startDate: Date(timeIntervalSince1970: 2_000_000_000), // Fixed date for determinism
            endDate: Date(timeIntervalSince1970: 2_000_001_800),
            organizer: "john.doe@company.com",
            calendarId: "primary",
            // swiftlint:disable:next force_unwrapping
            links: [URL(string: "https://meet.google.com/abc-defg-hij")!],
            provider: .meet
        )
    }

    private func createSampleEventWithoutLink() -> Event {
        Event(
            id: "snapshot-test-no-link",
            title: "In-Person Meeting",
            startDate: Date(timeIntervalSince1970: 2_000_000_000),
            endDate: Date(timeIntervalSince1970: 2_000_001_800),
            organizer: "jane.smith@company.com",
            calendarId: "primary"
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
            provider: .meet
        )
    }
}
