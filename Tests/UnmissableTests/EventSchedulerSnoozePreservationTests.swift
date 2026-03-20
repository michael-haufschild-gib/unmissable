@testable import Unmissable
import XCTest

@MainActor
final class EventSchedulerSnoozePreservationTests: XCTestCase {
    func testPreferenceReschedule_preservesExistingFutureSnoozeAlerts() async throws {
        let preferences = PreferencesManager()
        let scheduler = EventScheduler(preferencesManager: preferences)
        let overlayManager = TestSafeOverlayManager(isTestEnvironment: true)

        let event = Event(
            id: "snooze-preserve-event",
            title: "Snooze Preserve",
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(5400),
            calendarId: "primary"
        )

        await scheduler.startScheduling(events: [event], overlayManager: overlayManager)
        scheduler.scheduleSnooze(for: event, minutes: 30)

        XCTAssertTrue(
            scheduler.scheduledAlerts.contains { alert in
                if case .snooze = alert.alertType {
                    return alert.event.id == event.id
                }
                return false
            }
        )

        preferences.overlayShowMinutesBefore = 3
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            scheduler.scheduledAlerts.contains { alert in
                if case .snooze = alert.alertType { return alert.event.id == event.id }
                return false
            }
        }

        XCTAssertTrue(
            scheduler.scheduledAlerts.contains { alert in
                if case .snooze = alert.alertType {
                    return alert.event.id == event.id
                }
                return false
            },
            "Future snooze alert should survive preference-driven rescheduling"
        )
    }
}
