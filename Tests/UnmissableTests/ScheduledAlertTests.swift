@testable import Unmissable
import XCTest

final class ScheduledAlertTests: XCTestCase {
    // MARK: - isActive

    func testIsActive_trueWhenReferenceTimeIsAfterTrigger() {
        let alert = makeAlert(triggerDate: Date(timeIntervalSince1970: 1000))
        let now = Date(timeIntervalSince1970: 2000)

        XCTAssertTrue(alert.isActive(at: now))
    }

    func testIsActive_trueWhenReferenceTimeEqualsTrigger() {
        let triggerDate = Date(timeIntervalSince1970: 1000)
        let alert = makeAlert(triggerDate: triggerDate)

        XCTAssertTrue(alert.isActive(at: triggerDate))
    }

    func testIsActive_falseWhenReferenceTimeIsBeforeTrigger() {
        let alert = makeAlert(triggerDate: Date(timeIntervalSince1970: 2000))
        let now = Date(timeIntervalSince1970: 1000)

        XCTAssertFalse(alert.isActive(at: now))
    }

    // MARK: - timeUntilTrigger

    func testTimeUntilTrigger_positiveWhenInFuture() {
        let now = Date(timeIntervalSince1970: 1000)
        let alert = makeAlert(triggerDate: Date(timeIntervalSince1970: 1060))

        XCTAssertEqual(alert.timeUntilTrigger(from: now), 60.0, accuracy: 0.001)
    }

    func testTimeUntilTrigger_negativeWhenInPast() {
        let now = Date(timeIntervalSince1970: 2000)
        let alert = makeAlert(triggerDate: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(alert.timeUntilTrigger(from: now), -1000.0, accuracy: 0.001)
    }

    func testTimeUntilTrigger_zeroWhenExact() {
        let exact = Date(timeIntervalSince1970: 1000)
        let alert = makeAlert(triggerDate: exact)

        XCTAssertEqual(alert.timeUntilTrigger(from: exact), 0.0, accuracy: 0.001)
    }

    // MARK: - AlertType

    func testAlertType_reminderCarriesMinutesBefore() {
        let event = TestUtilities.createTestEvent()
        let alert = ScheduledAlert(
            event: event,
            triggerDate: Date(),
            alertType: .reminder(minutesBefore: 5)
        )

        if case let .reminder(minutes) = alert.alertType {
            XCTAssertEqual(minutes, 5)
        } else {
            XCTFail("Expected .reminder alert type")
        }
    }

    func testAlertType_snoozeCarriesUntilDate() {
        let event = TestUtilities.createTestEvent()
        let snoozeTarget = Date(timeIntervalSince1970: 2000)
        let alert = ScheduledAlert(
            event: event,
            triggerDate: snoozeTarget,
            alertType: .snooze(until: snoozeTarget)
        )

        if case let .snooze(until) = alert.alertType {
            XCTAssertEqual(until, snoozeTarget)
        } else {
            XCTFail("Expected .snooze alert type")
        }
    }

    func testAlertType_meetingStartHasNoAssociatedValue() {
        let event = TestUtilities.createTestEvent()
        let triggerDate = Date(timeIntervalSince1970: 3000)
        let alert = ScheduledAlert(
            event: event,
            triggerDate: triggerDate,
            alertType: .meetingStart
        )

        if case .meetingStart = alert.alertType {
            XCTAssertEqual(alert.triggerDate, triggerDate)
        } else {
            XCTFail("Expected .meetingStart alert type")
        }
    }

    // MARK: - Identity

    func testEachAlertHasUniqueId() {
        let event = TestUtilities.createTestEvent()
        let triggerDate = Date(timeIntervalSince1970: 1000)

        let alert1 = ScheduledAlert(
            event: event,
            triggerDate: triggerDate,
            alertType: .reminder(minutesBefore: 5)
        )
        let alert2 = ScheduledAlert(
            event: event,
            triggerDate: triggerDate,
            alertType: .reminder(minutesBefore: 5)
        )

        XCTAssertNotEqual(
            alert1.id, alert2.id,
            "Even identical alert data should produce unique IDs"
        )
    }

    func testDifferentAlertTypesForSameEvent() {
        let event = TestUtilities.createTestEvent()
        let now = Date()

        let reminder = ScheduledAlert(
            event: event,
            triggerDate: now,
            alertType: .reminder(minutesBefore: 5)
        )
        let snooze = ScheduledAlert(
            event: event,
            triggerDate: now,
            alertType: .snooze(until: now.addingTimeInterval(300))
        )
        let meetingStart = ScheduledAlert(
            event: event,
            triggerDate: now,
            alertType: .meetingStart
        )

        // All should have the same event but different types
        XCTAssertEqual(reminder.event.id, snooze.event.id)
        XCTAssertEqual(snooze.event.id, meetingStart.event.id)
        XCTAssertNotEqual(reminder.id, snooze.id)
        XCTAssertNotEqual(snooze.id, meetingStart.id)
    }

    // MARK: - isActive Boundary

    func testIsActive_justBeforeTrigger_notActive() {
        let trigger = Date(timeIntervalSince1970: 1000)
        let alert = makeAlert(triggerDate: trigger)
        let justBefore = Date(timeIntervalSince1970: 999.999)

        XCTAssertFalse(alert.isActive(at: justBefore))
    }

    // MARK: - Helpers

    private func makeAlert(triggerDate: Date) -> ScheduledAlert {
        ScheduledAlert(
            event: TestUtilities.createTestEvent(),
            triggerDate: triggerDate,
            alertType: .reminder(minutesBefore: 5)
        )
    }
}
