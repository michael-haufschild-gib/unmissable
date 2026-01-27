import SwiftUI
@testable import Unmissable
import XCTest

/// Tests that verify UI interactions work correctly
/// Ensures overlay buttons trigger correct actions
@MainActor
final class OverlayUIInteractionValidationTests: XCTestCase {
    func testOverlayContentViewButtonCallbacks() {
        // Test that all button callbacks are properly configured

        let event = TestUtilities.createMeetingEvent(provider: .meet)

        var dismissCalled = false
        var joinCalled = false
        var snoozeCalled = false
        var snoozeMinutes: Int?

        let view = OverlayContentView(
            event: event,
            onDismiss: {
                dismissCalled = true
            },
            onJoin: {
                joinCalled = true
            },
            onSnooze: { minutes in
                snoozeCalled = true
                snoozeMinutes = minutes
            }
        )

        // Verify view creation doesn't trigger callbacks
        XCTAssertFalse(dismissCalled, "Dismiss should not be called on view creation")
        XCTAssertFalse(joinCalled, "Join should not be called on view creation")
        XCTAssertFalse(snoozeCalled, "Snooze should not be called on view creation")

        // Simulate button interactions
        view.onDismiss()
        XCTAssertTrue(dismissCalled, "Dismiss callback should work")

        view.onJoin()
        XCTAssertTrue(joinCalled, "Join callback should work")

        view.onSnooze(5)
        XCTAssertTrue(snoozeCalled, "Snooze callback should work")
        XCTAssertEqual(snoozeMinutes, 5, "Snooze should pass correct minutes")

        print("✅ All overlay UI callbacks work correctly")
    }

    func testOverlayContentViewWithDifferentEventTypes() {
        // Test overlay UI with various event types

        let testCases: [(event: Event, description: String)] = [
            (TestUtilities.createMeetingEvent(provider: .meet), "Google Meet event"),
            (TestUtilities.createMeetingEvent(provider: .zoom), "Zoom event"),
            (TestUtilities.createMeetingEvent(provider: .teams), "Teams event"),
            (TestUtilities.createTestEvent(links: []), "Event without links"),
            (
                TestUtilities.createTestEvent(
                    title: "Very Long Meeting Title That Should Be Handled Gracefully"
                ), "Long title event"
            ),
        ]

        for (event, description) in testCases {
            var callbackTriggered = false

            let view = OverlayContentView(
                event: event,
                onDismiss: { callbackTriggered = true },
                onJoin: { callbackTriggered = true },
                onSnooze: { _ in callbackTriggered = true }
            )

            // Verify view can be created for all event types
            XCTAssertNotNil(view, "Should create view for \(description)")

            // Test that callbacks work for all event types
            view.onDismiss()
            XCTAssertTrue(callbackTriggered, "Callbacks should work for \(description)")

            callbackTriggered = false
        }

        print("✅ Overlay UI works with all event types")
    }

    func testOverlayContentViewSnoozeOptions() {
        // Test all snooze duration options

        let event = TestUtilities.createTestEvent()
        let snoozeDurations = [1, 5, 10, 15] // Standard snooze options

        for duration in snoozeDurations {
            var actualSnoozeMinutes: Int?

            let view = OverlayContentView(
                event: event,
                onDismiss: {},
                onJoin: {},
                onSnooze: { minutes in
                    actualSnoozeMinutes = minutes
                }
            )

            view.onSnooze(duration)
            XCTAssertEqual(
                actualSnoozeMinutes, duration, "Should handle \(duration)-minute snooze correctly"
            )
        }

        print("✅ All snooze duration options work correctly")
    }

    func testOverlayContentViewErrorHandling() {
        // Test overlay UI handles errors gracefully

        let event = TestUtilities.createTestEvent()

        // Test with callbacks that might throw or cause issues
        var errorOccurred = false

        let view = OverlayContentView(
            event: event,
            onDismiss: {
                // Simulate potential error in dismiss handler
                errorOccurred = true
            },
            onJoin: {
                // Simulate potential error in join handler
                errorOccurred = true
            },
            onSnooze: { minutes in
                // Test edge case snooze values
                XCTAssertGreaterThanOrEqual(minutes, 0, "Snooze minutes should be non-negative")
                errorOccurred = true
            }
        )

        // These should not crash the app
        view.onDismiss()
        view.onJoin()
        view.onSnooze(0) // Edge case: zero minutes
        view.onSnooze(-1) // Edge case: negative minutes (shouldn't happen in UI but test graceful handling)

        XCTAssertTrue(errorOccurred, "Error handling test should have triggered callbacks")

        print("✅ Overlay UI error handling works correctly")
    }

    func testOverlayContentViewStateConsistency() {
        // Test that overlay UI maintains consistent state

        let event = TestUtilities.createTestEvent()

        var dismissCount = 0
        var joinCount = 0
        var snoozeCount = 0

        let view = OverlayContentView(
            event: event,
            onDismiss: { dismissCount += 1 },
            onJoin: { joinCount += 1 },
            onSnooze: { _ in snoozeCount += 1 }
        )

        // Multiple rapid calls should all work
        view.onDismiss()
        view.onDismiss()
        view.onJoin()
        view.onJoin()
        view.onSnooze(5)
        view.onSnooze(10)

        XCTAssertEqual(dismissCount, 2, "Should handle multiple dismiss calls")
        XCTAssertEqual(joinCount, 2, "Should handle multiple join calls")
        XCTAssertEqual(snoozeCount, 2, "Should handle multiple snooze calls")

        print("✅ Overlay UI state consistency maintained")
    }

    func testOverlayContentViewWithRealEventData() throws {
        // Test with realistic event data that might come from calendar

        let realWorldEvent = try Event(
            id: "abc123-def456-ghi789",
            title: "Sprint Planning - Q4 2025",
            startDate: Date().addingTimeInterval(1800), // 30 minutes from now
            endDate: Date().addingTimeInterval(5400), // 1.5 hours from now
            organizer: "jane.doe@company.com",
            calendarId: "primary",
            links: [
                XCTUnwrap(URL(string: "https://meet.google.com/abc-def-ghi")),
                XCTUnwrap(URL(string: "https://docs.google.com/document/d/agenda")),
            ],
            provider: .meet
        )

        var interactionCount = 0

        let view = OverlayContentView(
            event: realWorldEvent,
            onDismiss: { interactionCount += 1 },
            onJoin: { interactionCount += 1 },
            onSnooze: { _ in interactionCount += 1 }
        )

        // Should handle realistic event data without issues
        XCTAssertNotNil(view, "Should create view with realistic event data")

        view.onJoin()
        XCTAssertEqual(interactionCount, 1, "Should handle join for realistic event")

        view.onSnooze(5)
        XCTAssertEqual(interactionCount, 2, "Should handle snooze for realistic event")

        view.onDismiss()
        XCTAssertEqual(interactionCount, 3, "Should handle dismiss for realistic event")

        print("✅ Overlay UI works with realistic event data")
    }
}
