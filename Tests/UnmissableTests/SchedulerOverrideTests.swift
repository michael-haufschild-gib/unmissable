import Foundation
import Testing
@testable import Unmissable

@MainActor
final class SchedulerOverrideTests {
    private var scheduler: EventScheduler
    private var preferencesManager: PreferencesManager
    private var overlayManager: TestSafeOverlayManager
    private var fixedDate: Date
    private let suiteName: String

    /// Default calendar ID matching the test events.
    private let calId = "cal-1"

    init() {
        fixedDate = Date()
        suiteName = "com.unmissable.scheduler-override-test.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: suiteName)!
        preferencesManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
        )
        let capturedDate = fixedDate
        scheduler = EventScheduler(
            preferencesManager: preferencesManager,
            linkParser: LinkParser(),
            now: { capturedDate },
        )
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// Builds a compound override key matching the scheduler's lookup format.
    private func overrideKey(_ eventId: String) -> String {
        EventOverride.compoundKey(eventId: eventId, calendarId: calId)
    }

    @Test
    func scheduleAlerts_withOverride_usesOverrideTiming() throws {
        let futureStart = fixedDate.addingTimeInterval(3600) // 1 hour from now
        let event = Event(
            id: "override-test",
            title: "Client Call",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(3600),
            calendarId: calId,
        )

        // Set override to 10 minutes
        scheduler.updateAlertOverrides([overrideKey("override-test"): 10])

        scheduler.scheduleWithoutMonitoring(
            events: [event],
            overlayManager: overlayManager,
        )

        // Should have exactly one alert at 10 minutes before
        let alerts = scheduler.scheduledAlerts.filter { $0.event.id == "override-test" }
        let alert = try #require(
            alerts.first,
            "Overridden event should have a scheduled alert",
        )
        let expectedTrigger = futureStart.addingTimeInterval(-600)
        #expect(
            alert.triggerDate == expectedTrigger,
            "Alert should trigger 10 minutes before event start",
        )
    }

    @Test
    func scheduleAlerts_zeroOverride_suppressesAllAlerts() {
        let futureStart = fixedDate.addingTimeInterval(3600)
        let event = Event(
            id: "suppressed-test",
            title: "Optional Standup",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(900),
            calendarId: calId,
        )

        // Set override to 0 (no alert)
        scheduler.updateAlertOverrides([overrideKey("suppressed-test"): 0])

        scheduler.scheduleWithoutMonitoring(
            events: [event],
            overlayManager: overlayManager,
        )

        let alerts = scheduler.scheduledAlerts.filter { $0.event.id == "suppressed-test" }
        #expect(
            alerts.isEmpty,
            "Zero override should suppress all alerts for this event",
        )
    }

    @Test
    func scheduleAlerts_noOverride_usesDefaultTiming() {
        let futureStart = fixedDate.addingTimeInterval(3600)
        let event = Event(
            id: "default-test",
            title: "Regular Meeting",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(3600),
            calendarId: calId,
        )

        // No overrides set
        scheduler.updateAlertOverrides([:])

        scheduler.scheduleWithoutMonitoring(
            events: [event],
            overlayManager: overlayManager,
        )

        // The overlay alert should use the global overlayShowMinutesBefore
        let overlayMinutes = preferencesManager.overlayShowMinutesBefore
        let expectedTrigger = futureStart.addingTimeInterval(
            -TimeInterval(overlayMinutes) * 60,
        )
        let overlayAlert = scheduler.scheduledAlerts.first { $0.event.id == "default-test" }
        #expect(
            overlayAlert?.triggerDate == expectedTrigger,
            "Default event should use global overlay timing",
        )
    }

    @Test
    func updateAlertOverrides_triggersReschedule() {
        let futureStart = fixedDate.addingTimeInterval(3600)
        let event = Event(
            id: "reschedule-test",
            title: "Meeting",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(3600),
            calendarId: calId,
        )

        scheduler.scheduleWithoutMonitoring(
            events: [event],
            overlayManager: overlayManager,
        )

        let initialTrigger = scheduler.scheduledAlerts
            .first { $0.event.id == "reschedule-test" }?.triggerDate

        // Now set an override — should trigger reschedule
        scheduler.updateAlertOverrides([overrideKey("reschedule-test"): 1])

        let updatedTrigger = scheduler.scheduledAlerts
            .first { $0.event.id == "reschedule-test" }?.triggerDate

        #expect(
            initialTrigger != updatedTrigger,
            "Updating overrides should reschedule with new timing",
        )

        let expectedTrigger = futureStart.addingTimeInterval(-60)
        #expect(
            updatedTrigger == expectedTrigger,
            "After override, alert should fire 1 minute before",
        )
    }

    @Test
    func scheduleAlerts_mixOfOverriddenAndDefault() throws {
        let futureStart = fixedDate.addingTimeInterval(3600)

        let criticalEvent = Event(
            id: "critical",
            title: "Client Demo",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(3600),
            calendarId: calId,
        )
        let optionalEvent = Event(
            id: "optional",
            title: "Team Standup",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(900),
            calendarId: calId,
        )
        let normalEvent = Event(
            id: "normal",
            title: "1:1",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(1800),
            calendarId: calId,
        )

        scheduler.updateAlertOverrides([
            overrideKey("critical"): 15,
            overrideKey("optional"): 0,
        ])

        scheduler.scheduleWithoutMonitoring(
            events: [criticalEvent, optionalEvent, normalEvent],
            overlayManager: overlayManager,
        )

        // Critical: overridden to 15 minutes
        let criticalAlert = scheduler.scheduledAlerts
            .first { $0.event.id == "critical" }
        #expect(
            criticalAlert?.triggerDate == futureStart.addingTimeInterval(-900),
            "Critical event should alert 15 minutes before",
        )

        // Optional: suppressed
        let optionalAlerts = scheduler.scheduledAlerts
            .filter { $0.event.id == "optional" }
        #expect(
            optionalAlerts.isEmpty,
            "Optional event with 0 override should have no alerts",
        )

        // Normal: uses default timing (global overlayShowMinutesBefore)
        let normalAlert = try #require(
            scheduler.scheduledAlerts.first { $0.event.id == "normal" },
            "Normal event should have a scheduled alert using default timing",
        )
        let expectedNormalTrigger = futureStart.addingTimeInterval(
            -TimeInterval(preferencesManager.overlayShowMinutesBefore) * 60,
        )
        #expect(
            normalAlert.triggerDate == expectedNormalTrigger,
            "Normal event should use global overlay timing",
        )
    }

    @Test
    func scheduleAlerts_overrideWithSoundEnabled_producesSingleAlert() throws {
        // When sound is enabled but an override is set, only one alert should fire
        // (the override controls both overlay and sound timing).
        preferencesManager.setPlayAlertSound(true)

        let futureStart = fixedDate.addingTimeInterval(3600)
        let event = Event(
            id: "sound-override",
            title: "Demo",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(3600),
            calendarId: calId,
        )

        scheduler.updateAlertOverrides([overrideKey("sound-override"): 10])

        scheduler.scheduleWithoutMonitoring(
            events: [event],
            overlayManager: overlayManager,
        )

        let alerts = scheduler.scheduledAlerts.filter { $0.event.id == "sound-override" }
        let alert = try #require(
            alerts.first, "Should produce exactly one alert for override + sound",
        )
        #expect(alerts.count == 1, "No separate sound alert")
        #expect(alert.event.id == "sound-override")
    }

    @Test
    func scheduleAlerts_overrideMissedAlertTime_triggersImmediately() {
        // Event starts in 5 minutes, override is 10 minutes before → alert time already passed
        let futureStart = fixedDate.addingTimeInterval(300) // 5 min from now
        let event = Event(
            id: "missed-override",
            title: "Urgent Call",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(1800),
            calendarId: calId,
        )

        scheduler.updateAlertOverrides([overrideKey("missed-override"): 10])

        scheduler.scheduleWithoutMonitoring(
            events: [event],
            overlayManager: overlayManager,
        )

        // Alert time was 10 min before = 5 min ago. Meeting hasn't started.
        // Scheduler should have triggered overlay immediately via missed-alert path.
        #expect(
            overlayManager.isOverlayVisible,
            "Missed override alert should trigger immediate overlay",
        )
        #expect(
            overlayManager.activeEvent?.id == "missed-override",
            "Immediate overlay should be for the correct event",
        )
    }
}
