import Foundation
import TestSupport
@testable import Unmissable
import XCTest

/// E2E tests for preference changes cascading through the full stack:
/// preference change → rescheduling → correct alert timing → overlay behavior.
@MainActor
final class PreferenceCascadeE2ETests: XCTestCase {
    private var env: E2ETestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        env = try await E2ETestEnvironment()
    }

    override func tearDown() async throws {
        env.tearDown()
        env = nil
        try await super.tearDown()
    }

    // MARK: - Default Alert Minutes

    func testDefaultAlertMinutesAffectsScheduledAlertTiming() async throws {
        env.preferencesManager.setOverlayShowMinutesBefore(5)
        env.preferencesManager.setPlayAlertSound(false)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-default-alert",
            minutesFromNow: 30,
        )
        try await env.seedAndSchedule([event])

        // Verify alert is scheduled for 5 minutes before
        let alert = try XCTUnwrap(env.eventScheduler.scheduledAlerts.first)
        if case let .reminder(minutes) = alert.alertType {
            XCTAssertEqual(minutes, 5)
        } else {
            XCTFail("Expected reminder alert")
        }

        // Change to 10 minutes before
        env.preferencesManager.setOverlayShowMinutesBefore(10)

        // Create new scheduler with updated prefs to verify the preference is read correctly
        let freshScheduler = EventScheduler(preferencesManager: env.preferencesManager, linkParser: LinkParser())
        let freshOverlay = TestSafeOverlayManager(isTestEnvironment: true)
        freshOverlay.setEventScheduler(freshScheduler)

        let fetched = try await env.fetchUpcomingEvents()
        await freshScheduler.startScheduling(events: fetched, overlayManager: freshOverlay)

        let freshAlert = try XCTUnwrap(freshScheduler.scheduledAlerts.first)
        if case let .reminder(minutes) = freshAlert.alertType {
            XCTAssertEqual(minutes, 10, "New scheduler should use updated preference of 10 minutes")
        } else {
            XCTFail("Expected reminder alert")
        }

        freshScheduler.stopScheduling()
    }

    // MARK: - Length-Based Timing

    func testLengthBasedTimingDifferentiatesEventDurations() async throws {
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

        let shortAlert = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { $0.event.id == "e2e-short" },
        )
        let longAlert = try XCTUnwrap(
            env.eventScheduler.scheduledAlerts.first { $0.event.id == "e2e-long" },
        )

        // They should have different trigger times due to different alert minutes
        XCTAssertNotEqual(
            shortAlert.triggerDate,
            longAlert.triggerDate,
            "Short and long events should have different alert timing",
        )

        // Short event should trigger closer to start time (1 minute before)
        let shortLeadTime = shortEvent.startDate.timeIntervalSince(shortAlert.triggerDate)
        let longLeadTime = longEvent.startDate.timeIntervalSince(longAlert.triggerDate)

        XCTAssertLessThan(
            shortLeadTime,
            longLeadTime,
            "Short meetings should have less lead time than long meetings",
        )
    }

    func testLengthBasedTimingAffectsSoundAlertTiming() {
        // Length-based timing affects SOUND alerts (via alertMinutes(for:)),
        // not OVERLAY alerts (which use overlayShowMinutesBefore).
        env.preferencesManager.setUseLengthBasedTiming(true)
        env.preferencesManager.setShortMeetingAlertMinutes(1)
        env.preferencesManager.setLongMeetingAlertMinutes(10)
        env.preferencesManager.setOverlayShowMinutesBefore(5)
        env.preferencesManager.setPlayAlertSound(true)

        let shortEvent = E2EEventBuilder.futureEvent(
            id: "e2e-lb-sound-short",
            minutesFromNow: 30,
            durationMinutes: 15, // Short: < 30 min
        )
        let longEvent = E2EEventBuilder.futureEvent(
            id: "e2e-lb-sound-long",
            minutesFromNow: 60,
            durationMinutes: 120, // Long: > 60 min
        )

        // Verify alertMinutes returns different values for different durations
        let shortAlertMinutes = env.preferencesManager.alertMinutes(for: shortEvent)
        let longAlertMinutes = env.preferencesManager.alertMinutes(for: longEvent)
        XCTAssertEqual(shortAlertMinutes, 1)
        XCTAssertEqual(longAlertMinutes, 10)

        // Toggle LB off — both should use defaultAlertMinutes
        env.preferencesManager.setUseLengthBasedTiming(false)
        env.preferencesManager.setDefaultAlertMinutes(3)

        let shortAlertMinutesOff = env.preferencesManager.alertMinutes(for: shortEvent)
        let longAlertMinutesOff = env.preferencesManager.alertMinutes(for: longEvent)
        XCTAssertEqual(shortAlertMinutesOff, 3, "Should use default when LB is off")
        XCTAssertEqual(longAlertMinutesOff, 3, "Should use default when LB is off")
    }

    // MARK: - Sound Alert Toggle

    func testSoundAlertToggleAffectsAlertCount() async throws {
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
        XCTAssertGreaterThan(
            alertsWithSound,
            alertsWithoutSound,
            "Enabling sound should add an additional alert when timings differ",
        )

        freshScheduler.stopScheduling()
    }

    // MARK: - Overlay Show Minutes Before

    func testOverlayShowMinutesBeforeAffectsWhenAlertFires() async throws {
        env.preferencesManager.setPlayAlertSound(false)

        let event = E2EEventBuilder.futureEvent(
            id: "e2e-show-minutes",
            minutesFromNow: 30,
        )

        // Schedule with 2 minutes before
        env.preferencesManager.setOverlayShowMinutesBefore(2)
        try await env.seedAndSchedule([event])

        let alert2Min = try XCTUnwrap(env.eventScheduler.scheduledAlerts.first)
        let leadTime2 = event.startDate.timeIntervalSince(alert2Min.triggerDate)

        // Re-schedule with 8 minutes before
        env.eventScheduler.stopScheduling()
        env.preferencesManager.setOverlayShowMinutesBefore(8)

        let fetched = try await env.fetchUpcomingEvents()
        await env.eventScheduler.startScheduling(
            events: fetched, overlayManager: env.overlayManager,
        )

        let alert8Min = try XCTUnwrap(env.eventScheduler.scheduledAlerts.first)
        let leadTime8 = event.startDate.timeIntervalSince(alert8Min.triggerDate)

        // 8-minute lead time should be larger than 2-minute lead time
        XCTAssertGreaterThan(leadTime8, leadTime2)
        XCTAssertGreaterThan(leadTime8, 7 * 60, "Lead time should be at least 7 minutes")
        XCTAssertLessThan(leadTime2, 3 * 60, "Lead time should be under 3 minutes")
    }
}
