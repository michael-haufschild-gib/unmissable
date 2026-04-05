import Foundation
import SwiftUI
import Testing
@testable import Unmissable

@MainActor
struct OverlayContentViewTests {
    @Test
    func snoozeCallbacksDoNotCauseDeadlock() async {
        let event = TestUtilities.createTestEvent()
        nonisolated(unsafe) var snoozeMinutes: Int?

        await confirmation("Snooze callback completes without deadlock") { confirm in
            let view = OverlayContentView(
                event: event,
                linkParser: LinkParser(),
                onDismiss: {
                    Issue.record("Dismiss should not be called during snooze test")
                },
                onJoin: {
                    Issue.record("Join should not be called during snooze test")
                },
                onSnooze: { minutes in
                    snoozeMinutes = minutes
                    confirm()
                },
            )

            // Simulate snooze action - this should not freeze the app
            view.onSnooze(5)
        }

        #expect(snoozeMinutes == 5)
    }

    @Test
    func dismissCallbackDoesNotCauseDeadlock() async {
        let event = TestUtilities.createTestEvent()
        nonisolated(unsafe) var dismissCalled = false

        await confirmation("Dismiss callback completes without deadlock") { confirm in
            let view = OverlayContentView(
                event: event,
                linkParser: LinkParser(),
                onDismiss: {
                    dismissCalled = true
                    confirm()
                },
                onJoin: {
                    Issue.record("Join should not be called during dismiss test")
                },
                onSnooze: { _ in
                    Issue.record("Snooze should not be called during dismiss test")
                },
            )

            // Simulate dismiss action - this should not freeze the app
            view.onDismiss()
        }

        #expect(dismissCalled)
    }

    @Test
    func joinMeetingCallbackDoesNotCauseDeadlock() async throws {
        let testURL = try #require(URL(string: "https://meet.google.com/test"))
        let event = TestUtilities.createTestEvent(links: [testURL], provider: .meet)
        nonisolated(unsafe) var joinedURL: URL?

        await confirmation("Join meeting callback completes without deadlock") { confirm in
            let view = OverlayContentView(
                event: event,
                linkParser: LinkParser(),
                onDismiss: {
                    Issue.record("Dismiss should not be called during join test")
                },
                onJoin: {
                    joinedURL = testURL
                    confirm()
                },
                onSnooze: { _ in
                    Issue.record("Snooze should not be called during join test")
                },
            )

            // Simulate join action - this should not freeze the app
            view.onJoin()
        }

        #expect(joinedURL == testURL)
    }

    @Test
    func snoozeCallbackReceivesDifferentDurations() {
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
                },
            )

            view.onSnooze(expectedMinutes)
            #expect(
                receivedMinutes == expectedMinutes,
                "Snooze callback should forward \(expectedMinutes) minutes",
            )
        }
    }

    @Test
    func callbacksRouteCorrectlyAcrossEventVariants() throws {
        let meetURL = try #require(URL(string: "https://meet.google.com/test"))
        let zoomURL = try #require(URL(string: "https://zoom.us/j/123456789"))

        let variants = [
            TestUtilities.createTestEvent(),
            TestUtilities.createTestEvent(
                links: [meetURL],
                provider: .meet,
            ),
            Event(
                id: "test-event-no-link",
                title: "In-Person Meeting",
                startDate: Date().addingTimeInterval(600),
                endDate: Date().addingTimeInterval(1800),
                organizer: "manager@example.com",
                calendarId: "test-calendar",
                links: [],
            ),
            Event(
                id: "test-event-zoom",
                title: "Zoom Planning",
                startDate: Date().addingTimeInterval(600),
                endDate: Date().addingTimeInterval(1800),
                organizer: "manager@example.com",
                calendarId: "test-calendar",
                links: [zoomURL],
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
                },
            )

            view.onDismiss()
            view.onJoin()
            view.onSnooze(10)

            #expect(dismissCalls == 1, "Dismiss callback should route for event: \(event.id)")
            #expect(joinCalls == 1, "Join callback should route for event: \(event.id)")
            #expect(snoozeCalls == 1, "Snooze callback should route for event: \(event.id)")
            #expect(snoozeMinutes == 10, "Snooze minutes should be forwarded for event: \(event.id)")
        }
    }
}
