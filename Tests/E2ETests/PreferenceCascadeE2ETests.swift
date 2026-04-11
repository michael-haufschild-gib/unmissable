import Foundation
import Testing
@testable import Unmissable

/// E2E tests for preference changes cascading through the full stack:
/// preference change → rescheduling → correct alert timing → overlay behavior.
@MainActor
struct PreferenceCascadeE2ETests {
    private let env: E2ETestEnvironment

    init() async throws {
        env = try await E2ETestEnvironment()
    }

    // MARK: - Default Alert Minutes

    @Test
    func defaultAlertMinutesAffectsScheduledAlertTiming() async throws {
        env.preferencesManager.setOverlayShowMinutesBefore(5)
        env.preferencesManager.setPlayAlertSound(false)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-default-alert",
            minutesFromNow: 30,
        )
        try await env.seedAndSchedule([event])

        // Verify alert is scheduled for 5 minutes before
        let alert = try #require(env.eventScheduler.scheduledAlerts.first)
        if case let .reminder(minutes) = alert.alertType {
            #expect(minutes == 5)
        } else {
            Issue.record("Expected reminder alert")
        }

        // Change to 10 minutes before
        env.preferencesManager.setOverlayShowMinutesBefore(10)

        // Create new scheduler with updated prefs to verify the preference is read correctly
        let freshScheduler = EventScheduler(preferencesManager: env.preferencesManager, linkParser: LinkParser())
        let freshOverlay = TestSafeOverlayManager(isTestEnvironment: true)
        freshOverlay.setEventScheduler(freshScheduler)

        let fetched = try await env.fetchUpcomingEvents()
        await freshScheduler.startScheduling(events: fetched, overlayManager: freshOverlay)

        let freshAlert = try #require(freshScheduler.scheduledAlerts.first)
        if case let .reminder(minutes) = freshAlert.alertType {
            #expect(minutes == 10, "New scheduler should use updated preference of 10 minutes")
        } else {
            Issue.record("Expected reminder alert")
        }

        freshScheduler.stopScheduling()
    }

    // MARK: - Length-Based Timing

    @Test
    func lengthBasedTimingDifferentiatesEventDurations() async throws {
        env.preferencesManager.setUseLengthBasedTiming(true)
        env.preferencesManager.setShortMeetingAlertMinutes(1)
        env.preferencesManager.setMediumMeetingAlertMinutes(5)
        env.preferencesManager.setLongMeetingAlertMinutes(10)
        env.preferencesManager.setPlayAlertSound(false)

        // Short meeting: 15 minutes
        let shortEvent = E2EEventBuilder.futureEvent(
            id: "e2e-short",
            title: "Quick Sync",
            minutesFromNow: 30,
            durationMinutes: 15,
        )
        // Long meeting: 90 minutes
        let longEvent = E2EEventBuilder.futureEvent(
            id: "e2e-long",
            title: "Planning Session",
            minutesFromNow: 60,
            durationMinutes: 90,
        )

        try await env.seedAndSchedule([shortEvent, longEvent])

        let shortAlert = try #require(
            env.eventScheduler.scheduledAlerts.first { $0.event.id == "e2e-short" },
        )
        let longAlert = try #require(
            env.eventScheduler.scheduledAlerts.first { $0.event.id == "e2e-long" },
        )

        // They should have different trigger times due to different alert minutes
        #expect(
            shortAlert.triggerDate != longAlert.triggerDate,
            "Short and long events should have different alert timing",
        )

        // Short event should trigger closer to start time (1 minute before)
        let shortLeadTime = shortEvent.startDate.timeIntervalSince(shortAlert.triggerDate)
        let longLeadTime = longEvent.startDate.timeIntervalSince(longAlert.triggerDate)

        #expect(
            shortLeadTime < longLeadTime,
            "Short meetings should have less lead time than long meetings",
        )
    }

    // MARK: - Sound Alert Toggle

    @Test
    func soundAlertToggleAffectsAlertCount() async throws {
        env.preferencesManager.setPlayAlertSound(false)
        env.preferencesManager.setOverlayShowMinutesBefore(5)
        env.preferencesManager.setDefaultAlertMinutes(3)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-sound-toggle",
            minutesFromNow: 30,
        )

        try await env.seedAndSchedule([event])
        let alertsWithoutSound = env.eventScheduler.scheduledAlerts.count

        // Enable sound — should create additional alert
        env.preferencesManager.setPlayAlertSound(true)

        let freshScheduler = EventScheduler(preferencesManager: env.preferencesManager, linkParser: LinkParser())
        let freshOverlay = TestSafeOverlayManager(isTestEnvironment: true)
        freshOverlay.setEventScheduler(freshScheduler)

        let fetched = try await env.fetchUpcomingEvents()
        await freshScheduler.startScheduling(events: fetched, overlayManager: freshOverlay)

        let alertsWithSound = freshScheduler.scheduledAlerts.count

        // When sound alert and overlay alert have different timings, we should get 2 alerts
        #expect(
            alertsWithSound > alertsWithoutSound,
            "Enabling sound should add an additional alert when timings differ",
        )

        freshScheduler.stopScheduling()
    }

    // MARK: - Overlay Show Minutes Before

    @Test
    func overlayShowMinutesBeforeAffectsWhenAlertFires() async throws {
        env.preferencesManager.setPlayAlertSound(false)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-show-minutes",
            minutesFromNow: 30,
        )

        // Schedule with 2 minutes before
        env.preferencesManager.setOverlayShowMinutesBefore(2)
        try await env.seedAndSchedule([event])

        let alert2Min = try #require(env.eventScheduler.scheduledAlerts.first)
        let leadTime2 = event.startDate.timeIntervalSince(alert2Min.triggerDate)

        // Re-schedule with 8 minutes before
        env.eventScheduler.stopScheduling()
        env.preferencesManager.setOverlayShowMinutesBefore(8)

        let fetched = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: fetched, overlayManager: env.overlayManager,
        )

        let alert8Min = try #require(env.eventScheduler.scheduledAlerts.first)
        let leadTime8 = event.startDate.timeIntervalSince(alert8Min.triggerDate)

        // 8-minute lead time should be larger than 2-minute lead time
        #expect(leadTime8 > leadTime2)
        #expect(leadTime8 > 7 * 60, "Lead time should be at least 7 minutes")
        #expect(leadTime2 < 3 * 60, "Lead time should be under 3 minutes")
    }
}
