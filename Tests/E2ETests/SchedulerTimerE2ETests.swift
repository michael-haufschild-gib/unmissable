import Foundation
import Testing
@testable import Unmissable

/// E2E tests for scheduler timer-based triggering and snooze re-fire.
/// These tests verify the real Timer-based code paths in EventScheduler.
@MainActor
struct SchedulerTimerE2ETests {
    private let env: E2ETestEnvironment

    init() async throws {
        env = try await E2ETestEnvironment()
    }

    // MARK: - Timer-Based Overlay Trigger

    @Test
    func schedulerTimerTriggersOverlayAtCorrectTime() async throws {
        // Set overlay to show 0 minutes before — alert triggers at event start time.
        // With test clock, the monitoring loop sleeps are instant (autoAdvance
        // moves clock forward), so the alert fires without wall-clock delay.
        env.preferencesManager.setOverlayShowMinutesBefore(0)

        let nearEvent = E2EEventBuilder.futureEvent(
            id: "e2e-timer-trigger",
            title: "Near Future Meeting",
            minutesFromNow: 1, // 1 minute from clock's "now"
        )

        try await env.seedAndSchedule([nearEvent], startMonitoring: true)
        defer { env.tearDown() }

        // Wait for monitoring loop to fire and show overlay.
        // Uses wall-clock polling instead of Task.yield + sleep which hangs
        // in Swift 6.3 due to MainActor starvation.
        await env.waitForOverlay()

        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent?.id == nearEvent.id)
    }

    // MARK: - Snooze Schedules Future Re-Fire

    @Test
    func snoozeCreatesScheduledAlertWithCorrectTiming() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-refire",
            title: "Snooze Refire Test",
            minutesFromNow: 15,
        )

        try await env.seedAndSchedule([event])

        // Show overlay and snooze
        env.overlayManager.showOverlayImmediately(for: event)
        #expect(env.overlayManager.isOverlayVisible)

        let snoozeMinutes = 5
        env.overlayManager.snoozeOverlay(for: snoozeMinutes)

        // Verify snooze alert is scheduled with correct future time
        let snoozeAlert = env.eventScheduler.scheduledAlerts.first { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }

        let alert = try #require(snoozeAlert)
        #expect(alert.event.id == event.id)

        // Trigger time should be ~5 minutes from test clock's "now"
        let secondsUntilSnooze = alert.triggerDate.timeIntervalSince(env.testClock.currentTime)
        #expect(secondsUntilSnooze > 4 * 60 - 5) // At least ~4 min 55s
        #expect(secondsUntilSnooze < 5 * 60 + 5) // At most ~5 min 5s
    }

    // MARK: - Snooze Preserved During Rescheduling

    @Test
    func snoozeAlertSurvivesRescheduling() async throws {
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-snooze-survive",
            minutesFromNow: 20,
        )

        try await env.seedAndSchedule([event])

        // Add a snooze
        env.eventScheduler.scheduleSnooze(for: event, minutes: 3)
        let initialSnoozeCount = env.eventScheduler.scheduledAlerts.count(where: { alert in
            if case .snooze = alert.alertType { return true }
            return false
        })
        #expect(initialSnoozeCount == 1)

        // Change preference to trigger rescheduling via Combine observer
        env.preferencesManager.setOverlayShowMinutesBefore(8)

        // Yield to let @Observable observation + rescheduling run
        // swiftlint:disable:next no_raw_task_sleep_in_tests - observation yield
        try await Task.sleep(for: .milliseconds(10))

        let postRescheduleSnoozeCount = env.eventScheduler.scheduledAlerts.count(where: { alert in
            if case .snooze = alert.alertType { return true }
            return false
        })
        #expect(
            postRescheduleSnoozeCount == 1,
            "Snooze alert should be preserved during rescheduling",
        )
    }

    // MARK: - Scheduler Correctly Handles App-Start-Late Scenario

    @Test
    func schedulerShowsOverlayImmediatelyForMissedAlertTime() async throws {
        // Simulate: app started late, event overlay alert time already passed
        // but meeting hasn't started yet
        env.preferencesManager.setOverlayShowMinutesBefore(10)

        // Event starts in 5 minutes — the 10-minute alert window already passed
        let event = E2EEventBuilder.futureEvent(
            id: "e2e-missed-alert",
            title: "Missed Alert Meeting",
            minutesFromNow: 5,
        )

        try await env.seedAndSchedule([event])

        // startScheduling calls showOverlay synchronously for missed alerts
        // before starting the monitoring loop, so the overlay is already visible.
        #expect(env.overlayManager.isOverlayVisible)
        #expect(env.overlayManager.activeEvent?.id == event.id)
    }

    // MARK: - Multiple Providers Through Full Stack

    @Test
    func allProviderTypesPreservedThroughDBAndScheduler() async throws {
        let providers: [Provider] = [.meet, .zoom, .teams, .webex, .generic]
        var events: [Event] = []

        for (index, provider) in providers.enumerated() {
            events.append(
                E2EEventBuilder.onlineMeeting(
                    id: "e2e-provider-\(provider.rawValue)",
                    title: "\(provider.rawValue) Meeting",
                    minutesFromNow: 15 + (index * 5),
                    provider: provider,
                ),
            )
        }

        try await env.seedAndSchedule(events)

        let fetched = try await env.fetchUpcomingEvents()

        // Known providers (meet, zoom, teams, webex) should be detected as online meetings
        let knownProviders: [Provider] = [.meet, .zoom, .teams, .webex]
        for provider in knownProviders {
            let event = try #require(
                fetched.first { $0.id == "e2e-provider-\(provider.rawValue)" },
                "Should find event for provider \(provider.rawValue)",
            )
            #expect(event.provider == provider)
            #expect(LinkParser().isOnlineMeeting(event), "\(provider.rawValue) should be online meeting")
            #expect(
                LinkParser().primaryLink(for: event) != nil,
                "\(provider.rawValue) should have a primary link",
            )
        }

        // Generic provider may or may not be detected as online meeting depending on
        // LinkParser — the important thing is the link is preserved
        let genericEvent = try #require(
            fetched.first { $0.id == "e2e-provider-generic" },
        )
        #expect(!genericEvent.links.isEmpty, "Generic event should still have links")
    }

    // MARK: - Database Search (FTS)

    @Test
    func databaseSearchFindsEventsByTitle() async throws {
        let events = [
            E2EEventBuilder.futureEvent(
                id: "e2e-search-standup",
                title: "Daily Standup",
                minutesFromNow: 10,
            ),
            E2EEventBuilder.futureEvent(
                id: "e2e-search-planning",
                title: "Sprint Planning",
                minutesFromNow: 30,
            ),
            E2EEventBuilder.futureEvent(
                id: "e2e-search-retro",
                title: "Team Retrospective",
                minutesFromNow: 60,
            ),
        ]

        try await env.seedEvents(events)

        let standupResults = try await env.databaseManager.searchEvents(query: "Standup")
        let standupMatch = try #require(standupResults.first)
        #expect(standupMatch.id == "e2e-search-standup")

        let sprintResults = try await env.databaseManager.searchEvents(query: "Sprint")
        let sprintMatch = try #require(sprintResults.first)
        #expect(sprintMatch.id == "e2e-search-planning")
    }

    // MARK: - Event Duration Calculation Through DB

    @Test
    func eventDurationPreservedThroughDatabase() async throws {
        let shortEvent = E2EEventBuilder.futureEvent(
            id: "e2e-duration-short",
            minutesFromNow: 10,
            durationMinutes: 15,
        )
        let longEvent = E2EEventBuilder.futureEvent(
            id: "e2e-duration-long",
            minutesFromNow: 30,
            durationMinutes: 120,
        )

        try await env.seedEvents([shortEvent, longEvent])
        let fetched = try await env.fetchUpcomingEvents()

        let fetchedShort = try #require(fetched.first { $0.id == "e2e-duration-short" })
        let fetchedLong = try #require(fetched.first { $0.id == "e2e-duration-long" })

        // Duration should be preserved through DB round-trip
        #expect(abs(fetchedShort.duration - 15 * 60) <= 1.0)
        #expect(abs(fetchedLong.duration - 120 * 60) <= 1.0)

        // Length-based timing should work with DB-fetched events
        env.preferencesManager.setUseLengthBasedTiming(true)
        env.preferencesManager.setShortMeetingAlertMinutes(2)
        env.preferencesManager.setLongMeetingAlertMinutes(10)

        let shortAlertMin = env.preferencesManager.alertMinutes(for: fetchedShort)
        let longAlertMin = env.preferencesManager.alertMinutes(for: fetchedLong)

        #expect(shortAlertMin == 2, "Short event from DB should use short alert minutes")
        #expect(longAlertMin == 10, "Long event from DB should use long alert minutes")
    }
}
