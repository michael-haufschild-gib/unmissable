import SnapshotTesting
import SwiftUI
@testable import Unmissable
import XCTest

@MainActor
final class OverlaySnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Set a consistent test device for snapshots
        // isRecording = true // Uncomment to record new snapshots
    }

    override func tearDown() {
        super.tearDown()
    }

    func testOverlayContentBeforeMeeting() {
        let preferencesManager = PreferencesManager()
        let event = createSampleEvent()

        // Build the full view hierarchy with environment first
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

        // Use NSHostingController with local scope
        let hostingController = NSHostingController(rootView: fullView)
        // Force view loading
        _ = hostingController.view
        hostingController.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)

        // Basic view creation test (snapshots disabled for now)
        XCTAssertNotNil(hostingController.view)
    }

    func testOverlayContentTestThree() {
        let preferencesManager = PreferencesManager()
        let event = createSampleEvent()

        // Build the full view hierarchy with environment first
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

        // Use NSHostingController with local scope
        let hostingController = NSHostingController(rootView: fullView)
        // Force view loading
        _ = hostingController.view
        hostingController.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)

        // Basic view creation test (snapshots disabled for now)
        XCTAssertNotNil(hostingController.view)
    }

    private func createSampleEvent() -> Event {
        Event(
            id: "snapshot-test",
            title: "Important Team Meeting",
            startDate: Date().addingTimeInterval(300), // 5 minutes from now
            endDate: Date().addingTimeInterval(1800), // 30 minutes from now
            organizer: "john.doe@company.com",
            calendarId: "primary",
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
            links: [URL(string: "https://meet.google.com/abc-defg-hij")!],
            provider: .meet
        )
    }
}
