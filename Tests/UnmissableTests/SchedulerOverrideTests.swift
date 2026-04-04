import TestSupport
@testable import Unmissable
import XCTest

@MainActor
final class SchedulerOverrideTests: XCTestCase {
    private var scheduler: EventScheduler!
    private var preferencesManager: PreferencesManager!
    private var overlayManager: TestSafeOverlayManager!
    private var fixedDate: Date!

    override func setUp() async throws {
        try await super.setUp()
        fixedDate = Date()
        let testDefaults = try XCTUnwrap(
            UserDefaults(suiteName: "test-\(UUID().uuidString)"),
        )
        preferencesManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
        )
        scheduler = EventScheduler(
            preferencesManager: preferencesManager,
            linkParser: LinkParser(),
            now: { [weak self] in self?.fixedDate ?? Date() },
        )
        overlayManager = TestSafeOverlayManager()
    }

    override func tearDown() async throws {
        scheduler = nil
        preferencesManager = nil
        overlayManager = nil
        fixedDate = nil
        try await super.tearDown()
    }

    func testScheduleAlerts_withOverride_usesOverrideTiming() throws {
        let futureStart = fixedDate.addingTimeInterval(3600) // 1 hour from now
        let event = Event(
            id: "override-test",
            title: "Client Call",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(3600),
            calendarId: "cal-1",
        )

        // Set override to 10 minutes
        scheduler.updateAlertOverrides(["override-test": 10])

        scheduler.scheduleWithoutMonitoring(
            events: [event],
            overlayManager: overlayManager,
        )

        // Should have exactly one alert at 10 minutes before
        let alerts = scheduler.scheduledAlerts.filter { $0.event.id == "override-test" }
        let alert = try XCTUnwrap(
            alerts.first,
            "Overridden event should have a scheduled alert",
        )
        let expectedTrigger = futureStart.addingTimeInterval(-600)
        XCTAssertEqual(
            alert.triggerDate,
            expectedTrigger,
            "Alert should trigger 10 minutes before event start",
        )
    }

    func testScheduleAlerts_zeroOverride_suppressesAllAlerts() {
        let futureStart = fixedDate.addingTimeInterval(3600)
        let event = Event(
            id: "suppressed-test",
            title: "Optional Standup",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(900),
            calendarId: "cal-1",
        )

        // Set override to 0 (no alert)
        scheduler.updateAlertOverrides(["suppressed-test": 0])

        scheduler.scheduleWithoutMonitoring(
            events: [event],
            overlayManager: overlayManager,
        )

        let alerts = scheduler.scheduledAlerts.filter { $0.event.id == "suppressed-test" }
        XCTAssertTrue(
            alerts.isEmpty,
            "Zero override should suppress all alerts for this event",
        )
    }

    func testScheduleAlerts_noOverride_usesDefaultTiming() {
        let futureStart = fixedDate.addingTimeInterval(3600)
        let event = Event(
            id: "default-test",
            title: "Regular Meeting",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(3600),
            calendarId: "cal-1",
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
        XCTAssertEqual(
            overlayAlert?.triggerDate,
            expectedTrigger,
            "Default event should use global overlay timing",
        )
    }

    func testUpdateAlertOverrides_triggersReschedule() {
        let futureStart = fixedDate.addingTimeInterval(3600)
        let event = Event(
            id: "reschedule-test",
            title: "Meeting",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(3600),
            calendarId: "cal-1",
        )

        scheduler.scheduleWithoutMonitoring(
            events: [event],
            overlayManager: overlayManager,
        )

        let initialTrigger = scheduler.scheduledAlerts
            .first { $0.event.id == "reschedule-test" }?.triggerDate

        // Now set an override — should trigger reschedule
        scheduler.updateAlertOverrides(["reschedule-test": 1])

        let updatedTrigger = scheduler.scheduledAlerts
            .first { $0.event.id == "reschedule-test" }?.triggerDate

        XCTAssertNotEqual(
            initialTrigger,
            updatedTrigger,
            "Updating overrides should reschedule with new timing",
        )

        let expectedTrigger = futureStart.addingTimeInterval(-60)
        XCTAssertEqual(
            updatedTrigger,
            expectedTrigger,
            "After override, alert should fire 1 minute before",
        )
    }

    func testScheduleAlerts_mixOfOverriddenAndDefault() throws {
        let futureStart = fixedDate.addingTimeInterval(3600)

        let criticalEvent = Event(
            id: "critical",
            title: "Client Demo",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(3600),
            calendarId: "cal-1",
        )
        let optionalEvent = Event(
            id: "optional",
            title: "Team Standup",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(900),
            calendarId: "cal-1",
        )
        let normalEvent = Event(
            id: "normal",
            title: "1:1",
            startDate: futureStart,
            endDate: futureStart.addingTimeInterval(1800),
            calendarId: "cal-1",
        )

        scheduler.updateAlertOverrides([
            "critical": 15,
            "optional": 0,
        ])

        scheduler.scheduleWithoutMonitoring(
            events: [criticalEvent, optionalEvent, normalEvent],
            overlayManager: overlayManager,
        )

        // Critical: overridden to 15 minutes
        let criticalAlert = scheduler.scheduledAlerts
            .first { $0.event.id == "critical" }
        XCTAssertEqual(
            criticalAlert?.triggerDate,
            futureStart.addingTimeInterval(-900),
            "Critical event should alert 15 minutes before",
        )

        // Optional: suppressed
        let optionalAlerts = scheduler.scheduledAlerts
            .filter { $0.event.id == "optional" }
        XCTAssertTrue(
            optionalAlerts.isEmpty,
            "Optional event with 0 override should have no alerts",
        )

        // Normal: uses default timing (global overlayShowMinutesBefore)
        let normalAlert = try XCTUnwrap(
            scheduler.scheduledAlerts.first { $0.event.id == "normal" },
            "Normal event should have a scheduled alert using default timing",
        )
        let expectedNormalTrigger = futureStart.addingTimeInterval(
            -TimeInterval(preferencesManager.overlayShowMinutesBefore) * 60,
        )
        XCTAssertEqual(
            normalAlert.triggerDate,
            expectedNormalTrigger,
            "Normal event should use global overlay timing",
        )
    }
}
