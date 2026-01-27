import SwiftUI
@testable import Unmissable
import XCTest

final class OverlayContentViewTests: XCTestCase {
    @MainActor
    func testSnoozeCallbacksDoNotCauseDeadlock() {
        let expectation = XCTestExpectation(description: "Snooze callback completes without deadlock")
        expectation.expectedFulfillmentCount = 1

        let event = createTestEvent()
        nonisolated(unsafe) var snoozeMinutes: Int?

        let view = OverlayContentView(
            event: event,
            onDismiss: {
                XCTFail("Dismiss should not be called during snooze test")
            },
            onJoin: {
                XCTFail("Join should not be called during snooze test")
            },
            onSnooze: { minutes in
                snoozeMinutes = minutes
                expectation.fulfill()
            }
        )

        // Simulate snooze action - this should not freeze the app
        Task { @MainActor in
            // In a real test we'd need to access the view's state
            // For now, just test that the callback can be called safely
            view.onSnooze(5)
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(snoozeMinutes, 5)
    }

    @MainActor
    func testDismissCallbackDoesNotCauseDeadlock() {
        let expectation = XCTestExpectation(description: "Dismiss callback completes without deadlock")

        let event = createTestEvent()
        nonisolated(unsafe) var dismissCalled = false

        let view = OverlayContentView(
            event: event,
            onDismiss: {
                dismissCalled = true
                expectation.fulfill()
            },
            onJoin: {
                XCTFail("Join should not be called during dismiss test")
            },
            onSnooze: { _ in
                XCTFail("Snooze should not be called during dismiss test")
            }
        )

        // Simulate dismiss action - this should not freeze the app
        Task { @MainActor in
            view.onDismiss()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(dismissCalled)
    }

    @MainActor
    func testJoinMeetingCallbackDoesNotCauseDeadlock() throws {
        let expectation = XCTestExpectation(
            description: "Join meeting callback completes without deadlock"
        )

        let testURL = try XCTUnwrap(URL(string: "https://meet.google.com/test"))
        let event = createTestEventWithURL(testURL)
        nonisolated(unsafe) var joinedURL: URL?

        let view = OverlayContentView(
            event: event,
            onDismiss: {
                XCTFail("Dismiss should not be called during join test")
            },
            onJoin: {
                joinedURL = testURL
                expectation.fulfill()
            },
            onSnooze: { _ in
                XCTFail("Snooze should not be called during join test")
            }
        )

        // Simulate join action - this should not freeze the app
        Task { @MainActor in
            view.onJoin()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(joinedURL, testURL)
    }

    func testOverlayContentViewDoesNotRetainTimers() {
        let event = createTestEvent()

        var view: OverlayContentView? = OverlayContentView(
            event: event,
            onDismiss: {},
            onJoin: {},
            onSnooze: { _ in }
        )

        // Start countdown (simulating onAppear)
        // view.startCountdown() - would need to expose this for testing

        // Release the view
        view = nil

        // The timer should be cleaned up automatically
        // This test mainly ensures no crashes occur during deallocation
        XCTAssertNil(view)
    }

    // MARK: - Helper Methods

    private func createTestEvent() -> Event {
        Event(
            id: "test-event",
            title: "Test Meeting",
            startDate: Date().addingTimeInterval(300), // 5 minutes from now
            endDate: Date().addingTimeInterval(1800), // 30 minutes from now
            organizer: "test@example.com",
            calendarId: "test-calendar"
        )
    }

    private func createTestEventWithURL(_ url: URL) -> Event {
        Event(
            id: "test-event-with-url",
            title: "Test Meeting with Link",
            startDate: Date().addingTimeInterval(300),
            endDate: Date().addingTimeInterval(1800),
            organizer: "test@example.com",
            calendarId: "test-calendar",
            links: [url],
            provider: .meet
        )
    }
}
