import Foundation
@testable import Unmissable
import XCTest

/// E2E tests for scheduler timer-based triggering and snooze re-fire.
/// These tests verify the real Timer-based code paths in EventScheduler.
@MainActor
final class SchedulerTimerE2ETests: XCTestCase {
    private var env: E2ETestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        env = try E2ETestEnvironment()
    }

    override func tearDown() async throws {
        env.tearDown()
        env = nil
        try await super.tearDown()
    }

    // MARK: - Timer-Based Overlay Trigger

    func testSchedulerTimerTriggersOverlayAtCorrectTime() async throws {
        // Set overlay to show 0 minutes before — this means "show at event start time"
        // For a very-near event, the scheduler should trigger via the
        // "missed alert time" path immediately
        env.preferencesManager.setOverlayShowMinutesBefore(0)

        let nearEvent = E2EEventBuilder.futureEvent(
            id: "e2e-timer-trigger",
            title: "Near Future Meeting",
            minutesFromNow: 1 // Very near
        )

        try await env.seedAndSchedule([nearEvent])

        // The scheduler should detect this event needs immediate overlay
        try await e2eWait(timeout: 10.0, description: "Overlay should appear for near event") {
            self.env.overlayManager.isOverlayVisible
        }

        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, nearEvent.id)
    }

    // MARK: - Snooze Schedules Future Re-Fire

    func testSnoozeCreatesScheduledAlertWithCorrectTiming() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-refire",
            title: "Snooze Refire Test",
            minutesFromNow: 15
        )

        try await env.seedAndSchedule([event])

        // Show overlay and snooze
        env.overlayManager.showOverlayImmediately(for: event)
        XCTAssertTrue(env.overlayManager.isOverlayVisible)

        let snoozeMinutes = 5
        env.overlayManager.snoozeOverlay(for: snoozeMinutes)

        // Verify snooze alert is scheduled with correct future time
        let snoozeAlert = env.eventScheduler.scheduledAlerts.first { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }

        let alert = try XCTUnwrap(snoozeAlert)
        XCTAssertEqual(alert.event.id, event.id)

        // Trigger time should be ~5 minutes in the future
        let secondsUntilSnooze = alert.triggerDate.timeIntervalSinceNow
        XCTAssertGreaterThan(secondsUntilSnooze, 4 * 60 - 5) // At least ~4 min 55s
        XCTAssertLessThan(secondsUntilSnooze, 5 * 60 + 5) // At most ~5 min 5s
    }

    // MARK: - Snooze Preserved During Rescheduling

    func testSnoozeAlertSurvivesRescheduling() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-survive",
            minutesFromNow: 20
        )

        try await env.seedAndSchedule([event])

        // Add a snooze
        env.eventScheduler.scheduleSnooze(for: event, minutes: 3)
        let initialSnoozeCount = env.eventScheduler.scheduledAlerts.count(where: { alert in
            if case .snooze = alert.alertType { return true }
            return false
        })
        XCTAssertEqual(initialSnoozeCount, 1)

        // Change preference to trigger rescheduling
        env.preferencesManager.setOverlayShowMinutesBefore(8)

        // Wait for rescheduling to complete
        try await e2eWait(timeout: 3.0, description: "Snooze should survive rescheduling") {
            self.env.eventScheduler.scheduledAlerts.contains { alert in
                if case .snooze = alert.alertType { return true }
                return false
            }
        }

        let postRescheduleSnoozeCount = env.eventScheduler.scheduledAlerts.count(where: { alert in
            if case .snooze = alert.alertType { return true }
            return false
        })
        XCTAssertEqual(
            postRescheduleSnoozeCount, 1,
            "Snooze alert should be preserved during rescheduling"
        )
    }

    // MARK: - Scheduler Correctly Handles App-Start-Late Scenario

    func testSchedulerShowsOverlayImmediatelyForMissedAlertTime() async throws {
        // Simulate: app started late, event overlay alert time already passed
        // but meeting hasn't started yet
        env.preferencesManager.setOverlayShowMinutesBefore(10)

        // Event starts in 5 minutes — the 10-minute alert window already passed
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-missed-alert",
            title: "Missed Alert Meeting",
            minutesFromNow: 5
        )

        try await env.seedAndSchedule([event])

        // Scheduler should detect the missed alert and show overlay immediately
        try await e2eWait(timeout: 5.0, description: "Overlay for missed-alert-time event") {
            self.env.overlayManager.isOverlayVisible
                && self.env.overlayManager.activeEvent?.id == event.id
        }

        XCTAssertTrue(env.overlayManager.isOverlayVisible)
        XCTAssertEqual(env.overlayManager.activeEvent?.id, event.id)
    }

    // MARK: - Multiple Providers Through Full Stack

    func testAllProviderTypesPreservedThroughDBAndScheduler() async throws {
        let providers: [Provider] = [.meet, .zoom, .teams, .webex, .generic]
        var events: [Event] = []

        for (index, provider) in providers.enumerated() {
            events.append(
                E2EEventBuilder.onlineMeeting(
                    id: "e2e-provider-\(provider.rawValue)",
                    title: "\(provider.rawValue) Meeting",
                    minutesFromNow: 15 + (index * 5),
                    provider: provider
                )
            )
        }

        try await env.seedAndSchedule(events)

        let fetched = try await env.fetchUpcomingEvents()

        // Known providers (meet, zoom, teams, webex) should be detected as online meetings
        let knownProviders: [Provider] = [.meet, .zoom, .teams, .webex]
        for provider in knownProviders {
            let event = try XCTUnwrap(
                fetched.first { $0.id == "e2e-provider-\(provider.rawValue)" },
                "Should find event for provider \(provider.rawValue)"
            )
            XCTAssertEqual(event.provider, provider)
            XCTAssertTrue(event.isOnlineMeeting, "\(provider.rawValue) should be online meeting")
            XCTAssertNotNil(event.primaryLink, "\(provider.rawValue) should have a primary link")
        }

        // Generic provider may or may not be detected as online meeting depending on
        // LinkParser — the important thing is the link is preserved
        let genericEvent = try XCTUnwrap(
            fetched.first { $0.id == "e2e-provider-generic" }
        )
        XCTAssertFalse(genericEvent.links.isEmpty, "Generic event should still have links")
    }

    // MARK: - Database Search (FTS)

    func testDatabaseSearchFindsEventsByTitle() async throws {
        let events = [
            E2EEventBuilder.futureEvent(
                id: "e2e-search-standup",
                title: "Daily Standup",
                minutesFromNow: 10
            ),
            E2EEventBuilder.futureEvent(
                id: "e2e-search-planning",
                title: "Sprint Planning",
                minutesFromNow: 30
            ),
            E2EEventBuilder.futureEvent(
                id: "e2e-search-retro",
                title: "Team Retrospective",
                minutesFromNow: 60
            ),
        ]

        try await env.seedEvents(events)

        let standupResults = try await env.databaseManager.searchEvents(query: "Standup")
        XCTAssertEqual(standupResults.count, 1)
        XCTAssertEqual(standupResults.first?.id, "e2e-search-standup")

        let sprintResults = try await env.databaseManager.searchEvents(query: "Sprint")
        XCTAssertEqual(sprintResults.count, 1)
        XCTAssertEqual(sprintResults.first?.id, "e2e-search-planning")
    }

    // MARK: - Event Duration Calculation Through DB

    func testEventDurationPreservedThroughDatabase() async throws {
        let shortEvent = E2EEventBuilder.futureEvent(
            id: "e2e-duration-short",
            minutesFromNow: 10,
            durationMinutes: 15
        )
        let longEvent = E2EEventBuilder.futureEvent(
            id: "e2e-duration-long",
            minutesFromNow: 30,
            durationMinutes: 120
        )

        try await env.seedEvents([shortEvent, longEvent])
        let fetched = try await env.fetchUpcomingEvents()

        let fetchedShort = try XCTUnwrap(fetched.first { $0.id == "e2e-duration-short" })
        let fetchedLong = try XCTUnwrap(fetched.first { $0.id == "e2e-duration-long" })

        // Duration should be preserved through DB round-trip
        XCTAssertEqual(fetchedShort.duration, 15 * 60, accuracy: 1.0)
        XCTAssertEqual(fetchedLong.duration, 120 * 60, accuracy: 1.0)

        // Length-based timing should work with DB-fetched events
        env.preferencesManager.useLengthBasedTiming = true
        env.preferencesManager.setShortMeetingAlertMinutes(2)
        env.preferencesManager.setLongMeetingAlertMinutes(10)

        let shortAlertMin = env.preferencesManager.alertMinutes(for: fetchedShort)
        let longAlertMin = env.preferencesManager.alertMinutes(for: fetchedLong)

        XCTAssertEqual(shortAlertMin, 2, "Short event from DB should use short alert minutes")
        XCTAssertEqual(longAlertMin, 10, "Long event from DB should use long alert minutes")
    }
}
