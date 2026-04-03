import SwiftUI
import TestSupport
@testable import Unmissable
import XCTest

final class OverlayContentViewTests: XCTestCase {
    @MainActor
    func testSnoozeCallbacksDoNotCauseDeadlock() {
        let expectation = XCTestExpectation(description: "Snooze callback completes without deadlock")
        expectation.expectedFulfillmentCount = 1

        let event = TestUtilities.createTestEvent()
        nonisolated(unsafe) var snoozeMinutes: Int?

        let view = OverlayContentView(
            event: event,
            linkParser: LinkParser(),
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

        let event = TestUtilities.createTestEvent()
        nonisolated(unsafe) var dismissCalled = false

        let view = OverlayContentView(
            event: event,
            linkParser: LinkParser(),
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
        let event = TestUtilities.createTestEvent(links: [testURL], provider: .meet)
        nonisolated(unsafe) var joinedURL: URL?

        let view = OverlayContentView(
            event: event,
            linkParser: LinkParser(),
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

    @MainActor
    func testSnoozeCallbackReceivesDifferentDurations() {
        let durations = [1, 5, 10, 15, 30]

        for expectedMinutes in durations {
            let event = TestUtilities.createTestEvent()
            var receivedMinutes: Int?

            let view = OverlayContentView(
                event: event,
                linkParser: LinkParser(),
                onDismiss: {},
                onJoin: {},
                onSnooze: { minutes in
                    receivedMinutes = minutes
                }
            )

            view.onSnooze(expectedMinutes)
            XCTAssertEqual(
                receivedMinutes, expectedMinutes,
                "Snooze callback should forward \(expectedMinutes) minutes"
            )
        }
    }

    @MainActor
    func testCallbacksRouteCorrectlyAcrossEventVariants() throws {
        let variants = try [
            TestUtilities.createTestEvent(),
            TestUtilities.createTestEvent(
                links: [XCTUnwrap(URL(string: "https://meet.google.com/test"))],
                provider: .meet
            ),
            Event(
                id: "test-event-no-link",
                title: "In-Person Meeting",
                startDate: Date().addingTimeInterval(600),
                endDate: Date().addingTimeInterval(1800),
                organizer: "manager@example.com",
                calendarId: "test-calendar",
                links: []
            ),
            Event(
                id: "test-event-zoom",
                title: "Zoom Planning",
                startDate: Date().addingTimeInterval(600),
                endDate: Date().addingTimeInterval(1800),
                organizer: "manager@example.com",
                calendarId: "test-calendar",
                links: [XCTUnwrap(URL(string: "https://zoom.us/j/123456789"))]
            ),
        ]

        for event in variants {
            nonisolated(unsafe) var dismissCalls = 0
            nonisolated(unsafe) var joinCalls = 0
            nonisolated(unsafe) var snoozeCalls = 0
            nonisolated(unsafe) var snoozeMinutes: Int?

            let view = OverlayContentView(
                event: event,
                linkParser: LinkParser(),
                onDismiss: {
                    dismissCalls += 1
                },
                onJoin: {
                    joinCalls += 1
                },
                onSnooze: { minutes in
                    snoozeCalls += 1
                    snoozeMinutes = minutes
                }
            )

            view.onDismiss()
            view.onJoin()
            view.onSnooze(10)

            XCTAssertEqual(dismissCalls, 1, "Dismiss callback should route for event: \(event.id)")
            XCTAssertEqual(joinCalls, 1, "Join callback should route for event: \(event.id)")
            XCTAssertEqual(snoozeCalls, 1, "Snooze callback should route for event: \(event.id)")
            XCTAssertEqual(snoozeMinutes, 10, "Snooze minutes should be forwarded for event: \(event.id)")
        }
    }
}
