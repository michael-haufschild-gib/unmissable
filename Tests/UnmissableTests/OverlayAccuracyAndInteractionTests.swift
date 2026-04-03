import Combine
import TestSupport
@testable import Unmissable
import XCTest

/// Tests for overlay display accuracy and interaction functionality.
/// Covers: wrong start time, wrong countdown, non-functioning timer, frozen overlay.
@MainActor
final class OverlayAccuracyAndInteractionTests: XCTestCase {
    private var overlayManager: TestSafeOverlayManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        cancellables = Set<AnyCancellable>()
        try await super.setUp()
    }

    override func tearDown() async throws {
        overlayManager.hideOverlay()
        cancellables.removeAll()
        overlayManager = nil
        try await super.tearDown()
    }

    // MARK: - Start Time Display Tests

    func testOverlayDisplaysCorrectStartTime() throws {
        let specificStartTime = Date().addingTimeInterval(600)
        let event = TestUtilities.createTestEvent(
            title: "Test Meeting",
            startDate: specificStartTime,
            endDate: specificStartTime.addingTimeInterval(3600)
        )

        overlayManager.showOverlayImmediately(for: event)

        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")
        let activeEvent = try XCTUnwrap(overlayManager.activeEvent)
        XCTAssertEqual(activeEvent.id, event.id, "Overlay should display the correct event")
        XCTAssertEqual(activeEvent.startDate, specificStartTime, "Overlay should show correct start time")
    }

    func testMultipleEventsShowCorrectStartTimes() throws {
        let firstEventTime = Date().addingTimeInterval(300)
        let secondEventTime = Date().addingTimeInterval(900)

        let firstEvent = TestUtilities.createTestEvent(
            title: "First Meeting", startDate: firstEventTime
        )
        let secondEvent = TestUtilities.createTestEvent(
            title: "Second Meeting", startDate: secondEventTime
        )

        overlayManager.showOverlayImmediately(for: firstEvent)
        var activeEvent = try XCTUnwrap(overlayManager.activeEvent)
        XCTAssertEqual(activeEvent.startDate, firstEventTime, "Should show first event time")

        overlayManager.showOverlayImmediately(for: secondEvent)
        activeEvent = try XCTUnwrap(overlayManager.activeEvent)
        XCTAssertEqual(activeEvent.startDate, secondEventTime, "Should show second event time")

        overlayManager.showOverlayImmediately(for: firstEvent)
        activeEvent = try XCTUnwrap(overlayManager.activeEvent)
        XCTAssertEqual(activeEvent.startDate, firstEventTime, "Should show first event time again")
    }

    // MARK: - Computed Time Remaining Tests

    func testTimeUntilMeetingReflectsCorrectRemainingTime() async throws {
        let futureTime = Date().addingTimeInterval(120) // 2 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlayImmediately(for: event)

        // Verify computed property reflects remaining time
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting > 0
        }

        let initialCountdown = overlayManager.timeUntilMeeting
        XCTAssertGreaterThan(initialCountdown, 115, "Initial countdown should be close to 2 minutes")
        XCTAssertLessThan(initialCountdown, 125, "Initial countdown should be close to 2 minutes")

        // Verify computed property tracks wall clock
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < initialCountdown - 0.9
        }

        let updatedCountdown = overlayManager.timeUntilMeeting
        XCTAssertLessThan(updatedCountdown, initialCountdown, "Computed time should decrease as wall clock advances")
    }

    func testTimeUntilMeetingInitializesImmediatelyOnShow() {
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        overlayManager.showOverlayImmediately(for: event)

        XCTAssertGreaterThan(
            overlayManager.timeUntilMeeting, 290, "Countdown should be initialized immediately"
        )
        XCTAssertLessThan(
            overlayManager.timeUntilMeeting, 310, "Initial countdown should be close to 5 minutes"
        )
    }

    func testTimeUntilMeetingDecreasesWithWallClock() async throws {
        let futureTime = Date().addingTimeInterval(300)
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlayImmediately(for: event)

        let initialCountdown = overlayManager.timeUntilMeeting

        // Verify computed property tracks elapsed wall clock time
        try await TestUtilities.waitForAsync(timeout: 5.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < initialCountdown - 2.0
        }

        let finalCountdown = overlayManager.timeUntilMeeting
        let totalDecrease = initialCountdown - finalCountdown
        XCTAssertGreaterThan(totalDecrease, 1.8, "Computed time should track wall clock decrease")
    }

    func testTimeUntilMeetingHandlesPastEvents() async throws {
        let pastTime = Date().addingTimeInterval(-60)
        let event = TestUtilities.createTestEvent(startDate: pastTime)

        overlayManager.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < 0
        }

        XCTAssertLessThan(
            overlayManager.timeUntilMeeting, 0, "Countdown should be negative for past events"
        )
        XCTAssertGreaterThan(
            overlayManager.timeUntilMeeting, -70, "Should be approximately -60 seconds"
        )
    }

    // MARK: - Computed Property Behavior Tests

    func testTimeUntilMeetingContinuouslyDecreases() async throws {
        let futureTime = Date().addingTimeInterval(180)
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting > 0
        }
        let initialTime = overlayManager.timeUntilMeeting

        // Verify computed property decreases over time
        try await TestUtilities.waitForAsync(timeout: 4.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < initialTime - 1.5
        }
        let updatedTime = overlayManager.timeUntilMeeting

        XCTAssertNotEqual(initialTime, updatedTime, "Computed time should change as wall clock advances")
        XCTAssertLessThan(updatedTime, initialTime, "Time should be decreasing")

        // Verify continued decrease
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < updatedTime - 0.5
        }
        let finalTime = overlayManager.timeUntilMeeting
        XCTAssertLessThan(finalTime, updatedTime, "Computed time should continue decreasing")
    }

    func testTimeUntilMeetingResetsWhenOverlayHidden() async throws {
        let futureTime = Date().addingTimeInterval(300)
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlayImmediately(for: event)
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting > 0
        }

        overlayManager.hideOverlay()
        let timeAfterHide = overlayManager.timeUntilMeeting

        // Verify value doesn't change (timer stopped) via a brief poll
        try? await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting != timeAfterHide
        }

        XCTAssertEqual(timeAfterHide, overlayManager.timeUntilMeeting, "Timer should stop when overlay is hidden")
    }

    func testTimeUntilMeetingUpdatesWhenEventChanges() async throws {
        let firstEvent = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))
        let secondEvent = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600))

        overlayManager.showOverlayImmediately(for: firstEvent)
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting > 0
        }
        let firstEventTime = overlayManager.timeUntilMeeting

        overlayManager.showOverlayImmediately(for: secondEvent)
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting > firstEventTime + 200
        }
        let secondEventTime = overlayManager.timeUntilMeeting

        XCTAssertGreaterThan(
            secondEventTime, firstEventTime, "Second event should have more time remaining"
        )

        // Verify timer is running for second event
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < secondEventTime - 0.5
        }

        XCTAssertLessThan(
            overlayManager.timeUntilMeeting, secondEventTime, "Timer should be running for second event"
        )
    }

    // MARK: - Overlay Interaction Tests

    func testOverlayRemainsInteractive() async throws {
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

        // Wait and verify overlay is still responsive
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            self.overlayManager.isOverlayVisible
        }

        overlayManager.hideOverlay()
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hideable (not frozen)")
    }

    func testOverlayResponseTimeIsReasonable() async throws {
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        let showStartTime = Date()
        overlayManager.showOverlayImmediately(for: event)
        let showDuration = Date().timeIntervalSince(showStartTime)
        XCTAssertLessThan(showDuration, 0.5, "Overlay should show quickly (not frozen)")

        try await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            self.overlayManager.isOverlayVisible
        }

        let hideStartTime = Date()
        overlayManager.hideOverlay()
        let hideDuration = Date().timeIntervalSince(hideStartTime)
        XCTAssertLessThan(hideDuration, 0.5, "Overlay should hide quickly (not frozen)")
    }

    // MARK: - Integration Tests

    func testOverlayManagerTimeComputationConsistency() async throws {
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(240))

        overlayManager.showOverlayImmediately(for: event)
        let firstReading = overlayManager.timeUntilMeeting

        try await TestUtilities.waitForAsync(timeout: 4.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < firstReading - 2.0
        }
        let secondReading = overlayManager.timeUntilMeeting

        XCTAssertGreaterThan(firstReading, secondReading, "Collected values should decrease")
    }

    func testOverlayPreservesComplexEventPayload() throws {
        let complexEvent = try Event(
            id: "accuracy-complex",
            title: "Complex Meeting with All Features",
            startDate: Date().addingTimeInterval(300),
            endDate: Date().addingTimeInterval(3900),
            organizer: "test@example.com",
            description: "Detailed planning session",
            location: "Conference Room A / Google Meet",
            attendees: [
                Attendee(
                    name: "John Doe", email: "john@example.com", status: .accepted, isOrganizer: true,
                    isSelf: false
                ),
                Attendee(name: "Jane Smith", email: "jane@example.com", status: .tentative, isSelf: false),
                Attendee(email: "user@example.com", status: .accepted, isSelf: true),
            ],
            calendarId: "primary",
            links: [XCTUnwrap(URL(string: "https://meet.google.com/test-room"))],
            provider: .meet
        )

        overlayManager.showOverlayImmediately(for: complexEvent)

        let activeEvent = try XCTUnwrap(overlayManager.activeEvent)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should show complex event")
        XCTAssertEqual(activeEvent.id, complexEvent.id)
        XCTAssertEqual(activeEvent.title, complexEvent.title)
        XCTAssertEqual(activeEvent.organizer, complexEvent.organizer)
        XCTAssertEqual(activeEvent.attendees.count, complexEvent.attendees.count)
        XCTAssertEqual(activeEvent.provider, complexEvent.provider)
    }

    func testComputedTimeAccuracyOverLongerPeriod() async throws {
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600))

        overlayManager.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting > 0
        }
        let startTime = Date()
        let initialCountdown = overlayManager.timeUntilMeeting

        // Wait for ~5 seconds of countdown
        try await TestUtilities.waitForAsync(timeout: 8.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < initialCountdown - 4.5
        }
        let endTime = Date()
        let finalCountdown = overlayManager.timeUntilMeeting

        let actualElapsed = endTime.timeIntervalSince(startTime)
        let countdownDecrease = initialCountdown - finalCountdown

        let difference = abs(actualElapsed - countdownDecrease)
        XCTAssertLessThan(difference, 0.5, "Timer should be accurate over longer periods")
    }

    // MARK: - Edge Cases

    func testZeroTimeRemainingHandled() async throws {
        let exactStartTime = Date().addingTimeInterval(1)
        let event = TestUtilities.createTestEvent(startDate: exactStartTime)

        overlayManager.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 4.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < 1
        }

        XCTAssertLessThan(overlayManager.timeUntilMeeting, 1, "Should handle zero/negative time")
        XCTAssertTrue(
            overlayManager.isOverlayVisible, "Overlay should still be visible briefly after start"
        )
    }

    func testAutoHideAfterMeetingStarts() async throws {
        let pastTime = Date().addingTimeInterval(-400) // Meeting started 6+ minutes ago
        let event = TestUtilities.createTestEvent(startDate: pastTime)

        overlayManager.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            !self.overlayManager.isOverlayVisible
        }

        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should auto-hide for old meetings")
    }
}
