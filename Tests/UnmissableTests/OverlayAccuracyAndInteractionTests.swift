import Foundation
import Testing
@testable import Unmissable

/// Tests for overlay display accuracy and interaction functionality.
/// Covers: wrong start time, wrong countdown, non-functioning timer, frozen overlay.
@MainActor
struct OverlayAccuracyAndInteractionTests {
    private var overlayManager: TestSafeOverlayManager

    init() {
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
    }

    // MARK: - Start Time Display Tests

    @Test
    func overlayDisplaysCorrectStartTime() throws {
        defer { overlayManager.hideOverlay() }
        let specificStartTime = Date().addingTimeInterval(600)
        let event = TestUtilities.createTestEvent(
            title: "Test Meeting",
            startDate: specificStartTime,
            endDate: specificStartTime.addingTimeInterval(3600),
        )

        overlayManager.showOverlayImmediately(for: event)

        #expect(overlayManager.isOverlayVisible, "Overlay should be visible")
        let activeEvent = try #require(overlayManager.activeEvent)
        #expect(activeEvent.id == event.id, "Overlay should display the correct event")
        #expect(activeEvent.startDate == specificStartTime, "Overlay should show correct start time")
    }

    @Test
    func multipleEventsShowCorrectStartTimes() throws {
        defer { overlayManager.hideOverlay() }
        let firstEventTime = Date().addingTimeInterval(300)
        let secondEventTime = Date().addingTimeInterval(900)

        let firstEvent = TestUtilities.createTestEvent(
            title: "First Meeting", startDate: firstEventTime,
        )
        let secondEvent = TestUtilities.createTestEvent(
            title: "Second Meeting", startDate: secondEventTime,
        )

        overlayManager.showOverlayImmediately(for: firstEvent)
        var activeEvent = try #require(overlayManager.activeEvent)
        #expect(activeEvent.startDate == firstEventTime, "Should show first event time")

        overlayManager.showOverlayImmediately(for: secondEvent)
        activeEvent = try #require(overlayManager.activeEvent)
        #expect(activeEvent.startDate == secondEventTime, "Should show second event time")

        overlayManager.showOverlayImmediately(for: firstEvent)
        activeEvent = try #require(overlayManager.activeEvent)
        #expect(activeEvent.startDate == firstEventTime, "Should show first event time again")
    }

    // MARK: - Computed Time Remaining Tests

    @Test
    func timeUntilMeetingReflectsCorrectRemainingTime() async throws {
        defer { overlayManager.hideOverlay() }
        let futureTime = Date().addingTimeInterval(120) // 2 minutes from now
        let event = TestUtilities.createTestEvent(startDate: futureTime)

        overlayManager.showOverlayImmediately(for: event)

        // Verify computed property reflects remaining time
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting > 0
        }

        let initialCountdown = overlayManager.timeUntilMeeting
        #expect(initialCountdown > 115, "Initial countdown should be close to 2 minutes")
        #expect(initialCountdown < 125, "Initial countdown should be close to 2 minutes")

        // Verify computed property tracks wall clock
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < initialCountdown - 0.9
        }

        let updatedCountdown = overlayManager.timeUntilMeeting
        #expect(updatedCountdown < initialCountdown, "Computed time should decrease as wall clock advances")
    }

    @Test
    func timeUntilMeetingInitializesImmediatelyOnShow() {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        overlayManager.showOverlayImmediately(for: event)

        #expect(
            overlayManager.timeUntilMeeting > 290, "Countdown should be initialized immediately",
        )
        #expect(
            overlayManager.timeUntilMeeting < 310, "Initial countdown should be close to 5 minutes",
        )
    }

    @Test
    func timeUntilMeetingDecreasesWithWallClock() async throws {
        defer { overlayManager.hideOverlay() }
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
        #expect(totalDecrease > 1.8, "Computed time should track wall clock decrease")
    }

    @Test
    func timeUntilMeetingHandlesPastEvents() async throws {
        defer { overlayManager.hideOverlay() }
        let pastTime = Date().addingTimeInterval(-60)
        let event = TestUtilities.createTestEvent(startDate: pastTime)

        overlayManager.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < 0
        }

        #expect(
            overlayManager.timeUntilMeeting < 0, "Countdown should be negative for past events",
        )
        #expect(
            overlayManager.timeUntilMeeting > -70, "Should be approximately -60 seconds",
        )
    }

    // MARK: - Computed Property Behavior Tests

    @Test
    func timeUntilMeetingContinuouslyDecreases() async throws {
        defer { overlayManager.hideOverlay() }
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

        #expect(initialTime != updatedTime, "Computed time should change as wall clock advances")
        #expect(updatedTime < initialTime, "Time should be decreasing")

        // Verify continued decrease
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < updatedTime - 0.5
        }
        let finalTime = overlayManager.timeUntilMeeting
        #expect(finalTime < updatedTime, "Computed time should continue decreasing")
    }

    @Test
    func timeUntilMeetingResetsWhenOverlayHidden() async throws {
        defer { overlayManager.hideOverlay() }
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

        #expect(timeAfterHide == overlayManager.timeUntilMeeting, "Timer should stop when overlay is hidden")
    }

    @Test
    func timeUntilMeetingUpdatesWhenEventChanges() async throws {
        defer { overlayManager.hideOverlay() }
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

        #expect(
            secondEventTime > firstEventTime, "Second event should have more time remaining",
        )

        // Verify timer is running for second event
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < secondEventTime - 0.5
        }

        #expect(
            overlayManager.timeUntilMeeting < secondEventTime, "Timer should be running for second event",
        )
    }

    // MARK: - Overlay Interaction Tests

    @Test
    func overlayRemainsInteractive() async throws {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        overlayManager.showOverlayImmediately(for: event)
        #expect(overlayManager.isOverlayVisible, "Overlay should be visible")

        // Wait and verify overlay is still responsive
        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            self.overlayManager.isOverlayVisible
        }

        overlayManager.hideOverlay()
        #expect(!overlayManager.isOverlayVisible, "Overlay should be hideable (not frozen)")
    }

    @Test
    func overlayResponseTimeIsReasonable() async throws {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(300))

        let showStartTime = Date()
        overlayManager.showOverlayImmediately(for: event)
        let showDuration = Date().timeIntervalSince(showStartTime)
        #expect(showDuration < 0.5, "Overlay should show quickly (not frozen)")

        try await TestUtilities.waitForAsync(timeout: 2.0) { @MainActor @Sendable in
            self.overlayManager.isOverlayVisible
        }

        let hideStartTime = Date()
        overlayManager.hideOverlay()
        let hideDuration = Date().timeIntervalSince(hideStartTime)
        #expect(hideDuration < 0.5, "Overlay should hide quickly (not frozen)")
    }

    // MARK: - Integration Tests

    @Test
    func overlayManagerTimeComputationConsistency() async throws {
        defer { overlayManager.hideOverlay() }
        let event = TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(240))

        overlayManager.showOverlayImmediately(for: event)
        let firstReading = overlayManager.timeUntilMeeting

        try await TestUtilities.waitForAsync(timeout: 4.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < firstReading - 2.0
        }
        let secondReading = overlayManager.timeUntilMeeting

        #expect(firstReading > secondReading, "Collected values should decrease")
    }

    @Test
    func overlayPreservesComplexEventPayload() throws {
        defer { overlayManager.hideOverlay() }
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
                    name: "John Doe",
                    email: "john@example.com",
                    status: .accepted,
                    isOrganizer: true,
                    isSelf: false,
                ),
                Attendee(name: "Jane Smith", email: "jane@example.com", status: .tentative, isSelf: false),
                Attendee(email: "user@example.com", status: .accepted, isSelf: true),
            ],
            calendarId: "primary",
            links: [#require(URL(string: "https://meet.google.com/test-room"))],
            provider: .meet,
        )

        overlayManager.showOverlayImmediately(for: complexEvent)

        let activeEvent = try #require(overlayManager.activeEvent)
        #expect(overlayManager.isOverlayVisible, "Overlay should show complex event")
        #expect(activeEvent.id == complexEvent.id)
        #expect(activeEvent.title == complexEvent.title)
        #expect(activeEvent.organizer == complexEvent.organizer)
        #expect(activeEvent.attendees.map(\.email) == complexEvent.attendees.map(\.email))
        #expect(activeEvent.provider == complexEvent.provider)
    }

    @Test
    func computedTimeAccuracyOverLongerPeriod() async throws {
        defer { overlayManager.hideOverlay() }
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
        #expect(difference < 0.5, "Timer should be accurate over longer periods")
    }

    // MARK: - Edge Cases

    @Test
    func zeroTimeRemainingHandled() async throws {
        defer { overlayManager.hideOverlay() }
        let exactStartTime = Date().addingTimeInterval(1)
        let event = TestUtilities.createTestEvent(startDate: exactStartTime)

        overlayManager.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 4.0) { @MainActor @Sendable in
            self.overlayManager.timeUntilMeeting < 1
        }

        #expect(overlayManager.timeUntilMeeting < 1, "Should handle zero/negative time")
        #expect(
            overlayManager.isOverlayVisible, "Overlay should still be visible briefly after start",
        )
    }

    @Test
    func autoHideAfterMeetingStarts() async throws {
        defer { overlayManager.hideOverlay() }
        let pastTime = Date().addingTimeInterval(-400) // Meeting started 6+ minutes ago
        let event = TestUtilities.createTestEvent(startDate: pastTime)

        overlayManager.showOverlayImmediately(for: event)

        try await TestUtilities.waitForAsync(timeout: 3.0) { @MainActor @Sendable in
            !self.overlayManager.isOverlayVisible
        }

        #expect(!overlayManager.isOverlayVisible, "Overlay should auto-hide for old meetings")
    }
}
