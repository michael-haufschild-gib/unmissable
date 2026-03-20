import SnapshotTesting
import SwiftUI
@testable import Unmissable
import XCTest

@MainActor
final class OverlaySnapshotTests: XCTestCase {
    func testOverlayContentBeforeMeeting_recursiveDescriptionSnapshot() {
        let hostingController = makeHostingController(event: createSampleEvent())
        assertSnapshot(of: hostingController, as: .recursiveDescription)
    }

    func testOverlayContentWithoutMeetingLink_recursiveDescriptionSnapshot() {
        let hostingController = makeHostingController(event: createSampleEventWithoutLink())
        assertSnapshot(of: hostingController, as: .recursiveDescription)
    }

    func testOverlayContentWithLongTitle_recursiveDescriptionSnapshot() {
        let hostingController = makeHostingController(event: createSampleEventWithLongTitle())
        assertSnapshot(of: hostingController, as: .recursiveDescription)
    }

    private func makeHostingController(event: Event) -> NSHostingController<AnyView> {
        let preferencesManager = PreferencesManager()
        let fullView = AnyView(
            OverlayContentView(
                event: event,
                onDismiss: {},
                onJoin: {},
                onSnooze: { _ in }
            )
            .environmentObject(preferencesManager)
            .frame(width: 1200, height: 800)
            .preferredColorScheme(.light)
        )

        let hostingController = NSHostingController(rootView: fullView)
        _ = hostingController.view
        hostingController.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        return hostingController
    }

    private func createSampleEvent() -> Event {
        Event(
            id: "snapshot-test",
            title: "Important Team Meeting",
            startDate: Date().addingTimeInterval(300), // 5 minutes from now
            endDate: Date().addingTimeInterval(1800), // 30 minutes from now
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
            startDate: Date().addingTimeInterval(300),
            endDate: Date().addingTimeInterval(1800),
            organizer: "jane.smith@company.com",
            calendarId: "primary"
        )
    }

    private func createSampleEventWithLongTitle() -> Event {
        Event(
            id: "snapshot-test-long",
            title:
            "Very Important Cross-Functional Strategic Planning Meeting with Multiple Stakeholders",
            startDate: Date().addingTimeInterval(300),
            endDate: Date().addingTimeInterval(1800),
            organizer: "strategic.planner@company.com",
            calendarId: "primary",
            // swiftlint:disable:next force_unwrapping
            links: [URL(string: "https://meet.google.com/abc-defg-hij")!],
            provider: .meet
        )
    }
}
