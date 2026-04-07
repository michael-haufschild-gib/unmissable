import Foundation
import Testing
@testable import Unmissable

@MainActor
struct EventSchedulerSnoozePreservationTests {
    @Test
    func preferenceReschedule_preservesExistingFutureSnoozeAlerts() async throws {
        let preferences = PreferencesManager(themeManager: ThemeManager())
        let scheduler = EventScheduler(preferencesManager: preferences, linkParser: LinkParser())
        let overlayManager = TestSafeOverlayManager(isTestEnvironment: true)

        let event = Event(
            id: "snooze-preserve-event",
            title: "Snooze Preserve",
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(5400),
            calendarId: "primary",
        )

        await scheduler.startScheduling(events: [event], overlayManager: overlayManager)
        scheduler.scheduleSnooze(for: event, minutes: 30)

        #expect(
            scheduler.scheduledAlerts.contains { alert in
                if case .snooze = alert.alertType {
                    return alert.event.id == event.id
                }
                return false
            },
        )

        preferences.setOverlayShowMinutesBefore(3)
        try await TestUtilities.waitForAsync(timeout: 10.0) { @MainActor @Sendable in
            scheduler.scheduledAlerts.contains { alert in
                if case .snooze = alert.alertType { return alert.event.id == event.id }
                return false
            }
        }

        #expect(
            scheduler.scheduledAlerts.contains { alert in
                if case .snooze = alert.alertType {
                    return alert.event.id == event.id
                }
                return false
            },
            "Future snooze alert should survive preference-driven rescheduling",
        )
    }
}
