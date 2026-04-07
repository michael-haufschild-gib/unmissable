import Foundation
import Testing
@testable import Unmissable

@MainActor
struct ScheduledAlertTests {
    // MARK: - isActive

    @Test
    func isActive_trueWhenReferenceTimeIsAfterTrigger() {
        let alert = makeAlert(triggerDate: Date(timeIntervalSince1970: 1000))
        let now = Date(timeIntervalSince1970: 2000)

        #expect(alert.isActive(at: now))
    }

    @Test
    func isActive_trueWhenReferenceTimeEqualsTrigger() {
        let triggerDate = Date(timeIntervalSince1970: 1000)
        let alert = makeAlert(triggerDate: triggerDate)

        #expect(alert.isActive(at: triggerDate))
    }

    @Test
    func isActive_falseWhenReferenceTimeIsBeforeTrigger() {
        let alert = makeAlert(triggerDate: Date(timeIntervalSince1970: 2000))
        let now = Date(timeIntervalSince1970: 1000)

        #expect(!alert.isActive(at: now))
    }

    // MARK: - timeUntilTrigger

    @Test
    func timeUntilTrigger_positiveWhenInFuture() {
        let now = Date(timeIntervalSince1970: 1000)
        let alert = makeAlert(triggerDate: Date(timeIntervalSince1970: 1060))

        #expect(abs(alert.timeUntilTrigger(from: now) - 60.0) <= 0.001)
    }

    @Test
    func timeUntilTrigger_negativeWhenInPast() {
        let now = Date(timeIntervalSince1970: 2000)
        let alert = makeAlert(triggerDate: Date(timeIntervalSince1970: 1000))

        #expect(abs(alert.timeUntilTrigger(from: now) - -1000.0) <= 0.001)
    }

    @Test
    func timeUntilTrigger_zeroWhenExact() {
        let exact = Date(timeIntervalSince1970: 1000)
        let alert = makeAlert(triggerDate: exact)

        #expect(abs(alert.timeUntilTrigger(from: exact)) <= 0.001)
    }

    // MARK: - AlertType

    @Test
    func alertType_reminderCarriesMinutesBefore() {
        let event = TestUtilities.createTestEvent()
        let alert = ScheduledAlert(
            event: event,
            triggerDate: Date(),
            alertType: .reminder(minutesBefore: 5),
        )

        if case let .reminder(minutes) = alert.alertType {
            #expect(minutes == 5)
        } else {
            Issue.record("Expected .reminder alert type")
        }
    }

    @Test
    func alertType_snoozeCarriesUntilDate() {
        let event = TestUtilities.createTestEvent()
        let snoozeTarget = Date(timeIntervalSince1970: 2000)
        let alert = ScheduledAlert(
            event: event,
            triggerDate: snoozeTarget,
            alertType: .snooze(until: snoozeTarget),
        )

        if case let .snooze(until) = alert.alertType {
            #expect(until == snoozeTarget)
        } else {
            Issue.record("Expected .snooze alert type")
        }
    }

    @Test
    func alertType_meetingStartHasNoAssociatedValue() {
        let event = TestUtilities.createTestEvent()
        let triggerDate = Date(timeIntervalSince1970: 3000)
        let alert = ScheduledAlert(
            event: event,
            triggerDate: triggerDate,
            alertType: .meetingStart,
        )

        if case .meetingStart = alert.alertType {
            #expect(alert.triggerDate == triggerDate)
        } else {
            Issue.record("Expected .meetingStart alert type")
        }
    }

    // MARK: - Identity

    @Test
    func eachAlertHasUniqueId() {
        let event = TestUtilities.createTestEvent()
        let triggerDate = Date(timeIntervalSince1970: 1000)

        let alert1 = ScheduledAlert(
            event: event,
            triggerDate: triggerDate,
            alertType: .reminder(minutesBefore: 5),
        )
        let alert2 = ScheduledAlert(
            event: event,
            triggerDate: triggerDate,
            alertType: .reminder(minutesBefore: 5),
        )

        #expect(
            alert1.id != alert2.id,
            "Even identical alert data should produce unique IDs",
        )
    }

    @Test
    func differentAlertTypesForSameEvent() {
        let event = TestUtilities.createTestEvent()
        let now = Date()

        let reminder = ScheduledAlert(
            event: event,
            triggerDate: now,
            alertType: .reminder(minutesBefore: 5),
        )
        let snooze = ScheduledAlert(
            event: event,
            triggerDate: now,
            alertType: .snooze(until: now.addingTimeInterval(300)),
        )
        let meetingStart = ScheduledAlert(
            event: event,
            triggerDate: now,
            alertType: .meetingStart,
        )

        // All should have the same event but different types
        #expect(reminder.event.id == snooze.event.id)
        #expect(snooze.event.id == meetingStart.event.id)
        #expect(reminder.id != snooze.id)
        #expect(snooze.id != meetingStart.id)
    }

    // MARK: - isActive Boundary

    @Test
    func isActive_justBeforeTrigger_notActive() {
        let trigger = Date(timeIntervalSince1970: 1000)
        let alert = makeAlert(triggerDate: trigger)
        let justBefore = Date(timeIntervalSince1970: 999.999)

        #expect(!alert.isActive(at: justBefore))
    }

    // MARK: - Helpers

    private func makeAlert(triggerDate: Date) -> ScheduledAlert {
        ScheduledAlert(
            event: TestUtilities.createTestEvent(),
            triggerDate: triggerDate,
            alertType: .reminder(minutesBefore: 5),
        )
    }
}
