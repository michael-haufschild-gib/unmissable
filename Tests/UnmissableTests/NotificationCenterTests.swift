import TestSupport
@testable import Unmissable
import XCTest

// MARK: - Notification Center Alert Mode Tests

final class NotificationCenterTests: XCTestCase {
    private var eventScheduler: EventScheduler!
    private var mockPreferences: PreferencesManager!
    private var overlayManager: TestSafeOverlayManager!
    private var notificationManager: TestSafeNotificationManager!
    /// Fixed reference time for deterministic scheduling.
    private var fixedDate: Date!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        fixedDate = Date()
        mockPreferences = TestUtilities.createTestPreferencesManager()
        mockPreferences.testOverlayShowMinutesBefore = 2
        let capturedDate = try XCTUnwrap(fixedDate)
        eventScheduler = EventScheduler(
            preferencesManager: mockPreferences,
            linkParser: LinkParser(),
            now: { capturedDate },
        )
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        notificationManager = TestSafeNotificationManager()
        eventScheduler.setNotificationManager(notificationManager)
    }

    override func tearDown() {
        eventScheduler = nil
        mockPreferences = nil
        overlayManager = nil
        notificationManager = nil
        fixedDate = nil
        super.tearDown()
    }

    // MARK: - AlertMode Enum

    @MainActor
    func testAlertMode_rawValueRoundTrip() {
        for mode in AlertMode.allCases {
            let decoded = AlertMode(rawValue: mode.rawValue)
            XCTAssertEqual(decoded, mode, "Round-trip failed for \(mode)")
        }
    }

    @MainActor
    func testAlertMode_displayNames() {
        XCTAssertEqual(AlertMode.overlay.displayName, "Full-Screen Overlay")
        XCTAssertEqual(AlertMode.notification.displayName, "Notification")
        XCTAssertEqual(AlertMode.none.displayName, "None")
    }

    @MainActor
    func testAlertMode_rawValues() {
        XCTAssertEqual(AlertMode.overlay.rawValue, "overlay")
        XCTAssertEqual(AlertMode.notification.rawValue, "notification")
        XCTAssertEqual(AlertMode.none.rawValue, "none")
    }

    // MARK: - CalendarInfo AlertMode

    @MainActor
    func testCalendarInfo_defaultAlertModeIsOverlay() {
        let calendar = CalendarInfo(id: "cal-1", name: "Work")
        XCTAssertEqual(calendar.alertMode, .overlay)
    }

    @MainActor
    func testCalendarInfo_withAlertModePreservesOtherFields() {
        let calendar = CalendarInfo(
            id: "cal-1",
            name: "Work",
            isSelected: true,
            isPrimary: true,
            colorHex: "#FF0000",
            sourceProvider: .google,
            alertMode: .overlay,
        )

        let updated = calendar.withAlertMode(.notification)

        XCTAssertEqual(updated.id, "cal-1")
        XCTAssertEqual(updated.name, "Work")
        XCTAssertTrue(updated.isSelected)
        XCTAssertTrue(updated.isPrimary)
        XCTAssertEqual(updated.colorHex, "#FF0000")
        XCTAssertEqual(updated.sourceProvider, .google)
        XCTAssertEqual(updated.alertMode, .notification)
    }

    @MainActor
    func testCalendarInfo_withSelectionPreservesAlertMode() {
        let calendar = CalendarInfo(
            id: "cal-1",
            name: "Work",
            isSelected: false,
            alertMode: .notification,
        )

        let updated = calendar.withSelection(true)

        XCTAssertTrue(updated.isSelected)
        XCTAssertEqual(updated.alertMode, .notification)
    }

    // MARK: - Overlay Mode (Default)

    @MainActor
    func testDefaultAlertMode_usesOverlay() async {
        let event = TestUtilities.createTestEvent(
            startDate: fixedDate.addingTimeInterval(60),
            calendarId: "cal-1",
        )

        // Alert fires at 5 min before, event is 1 min away → missed, triggers immediately
        mockPreferences.testOverlayShowMinutesBefore = 5
        await eventScheduler.scheduleWithoutMonitoring(
            events: [event], overlayManager: overlayManager,
        )

        XCTAssertTrue(overlayManager.isOverlayVisible, "Default mode should show overlay")
        XCTAssertEqual(overlayManager.activeEvent?.id, event.id)
        XCTAssertEqual(notificationManager.sentNotifications.map(\.event.id), [])
    }

    // MARK: - Notification Mode

    @MainActor
    func testNotificationMode_sendsNotificationNotOverlay() async throws {
        eventScheduler.updateCalendarAlertModes(["cal-notif": .notification])

        let event = TestUtilities.createTestEvent(
            id: "evt-notif",
            startDate: fixedDate.addingTimeInterval(60),
            calendarId: "cal-notif",
        )

        mockPreferences.testOverlayShowMinutesBefore = 5
        await eventScheduler.scheduleWithoutMonitoring(
            events: [event], overlayManager: overlayManager,
        )

        XCTAssertFalse(overlayManager.isOverlayVisible, "Notification mode should NOT show overlay")

        // Wait for the async Task that sends the notification
        let notifMgr = try XCTUnwrap(notificationManager)
        try await TestUtilities.waitForAsync {
            await MainActor.run { notifMgr.sentNotifications.count == 1 }
        }

        XCTAssertEqual(notificationManager.sentNotifications.first?.event.id, "evt-notif")
    }

    // MARK: - None Mode

    @MainActor
    func testNoneMode_suppressesAllAlerts() async throws {
        eventScheduler.updateCalendarAlertModes(["cal-silent": .none])

        let event = TestUtilities.createTestEvent(
            startDate: fixedDate.addingTimeInterval(60),
            calendarId: "cal-silent",
        )

        mockPreferences.testOverlayShowMinutesBefore = 5
        await eventScheduler.scheduleWithoutMonitoring(
            events: [event], overlayManager: overlayManager,
        )

        // Negative test: wait a fixed interval, then verify nothing happened
        // swiftlint:disable:next no_raw_task_sleep_in_tests
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertEqual(notificationManager.sentNotifications.map(\.event.id), [])
    }

    // MARK: - Snooze Always Uses Overlay

    @MainActor
    func testSnooze_alwaysUsesOverlay_regardlessOfCalendarMode() async {
        eventScheduler.updateCalendarAlertModes(["cal-notif": .notification])

        let event = TestUtilities.createTestEvent(
            id: "snooze-evt",
            startDate: fixedDate.addingTimeInterval(300),
            calendarId: "cal-notif",
        )

        await eventScheduler.scheduleWithoutMonitoring(
            events: [event], overlayManager: overlayManager,
        )

        XCTAssertFalse(overlayManager.isOverlayVisible)

        eventScheduler.scheduleSnooze(for: event, minutes: 1)

        let snoozeAlerts = eventScheduler.scheduledAlerts.filter {
            if case .snooze = $0.alertType { return true }
            return false
        }
        // Verify both presence and identity of the snooze alert
        XCTAssertEqual(snoozeAlerts.first?.event.id, "snooze-evt")
        XCTAssertEqual(snoozeAlerts.first?.event.calendarId, "cal-notif")
    }

    // MARK: - Mixed Calendars

    @MainActor
    func testMixedModes_routeCorrectly() async throws {
        eventScheduler.updateCalendarAlertModes([
            "cal-overlay": .overlay,
            "cal-notif": .notification,
            "cal-silent": .none,
        ])

        let overlayEvent = TestUtilities.createTestEvent(
            id: "evt-overlay",
            startDate: fixedDate.addingTimeInterval(60),
            calendarId: "cal-overlay",
        )
        let notifEvent = TestUtilities.createTestEvent(
            id: "evt-notif",
            startDate: fixedDate.addingTimeInterval(60),
            calendarId: "cal-notif",
        )
        let silentEvent = TestUtilities.createTestEvent(
            id: "evt-silent",
            startDate: fixedDate.addingTimeInterval(60),
            calendarId: "cal-silent",
        )

        mockPreferences.testOverlayShowMinutesBefore = 5
        await eventScheduler.scheduleWithoutMonitoring(
            events: [overlayEvent, notifEvent, silentEvent],
            overlayManager: overlayManager,
        )

        // Wait for the notification async task
        let notifMgr = try XCTUnwrap(notificationManager)
        try await TestUtilities.waitForAsync {
            await MainActor.run { notifMgr.sentNotifications.count == 1 }
        }

        // Overlay event should have triggered overlay
        XCTAssertTrue(overlayManager.isOverlayVisible)

        // Notification event should have sent exactly one notification
        XCTAssertEqual(notificationManager.sentNotifications.first?.event.id, "evt-notif")
        // Verify no extra notifications from overlay or silent events
        let notifEventIds = notificationManager.sentNotifications.map(\.event.id)
        XCTAssertEqual(notifEventIds, ["evt-notif"])
    }

    // MARK: - Unknown Calendar Defaults to Overlay

    @MainActor
    func testUnknownCalendar_defaultsToOverlay() async {
        eventScheduler.updateCalendarAlertModes(["other-cal": .notification])

        let event = TestUtilities.createTestEvent(
            id: "unknown-evt",
            startDate: fixedDate.addingTimeInterval(60),
            calendarId: "unknown-cal",
        )

        mockPreferences.testOverlayShowMinutesBefore = 5
        await eventScheduler.scheduleWithoutMonitoring(
            events: [event], overlayManager: overlayManager,
        )

        XCTAssertTrue(overlayManager.isOverlayVisible)
        XCTAssertEqual(overlayManager.activeEvent?.id, "unknown-evt")
    }

    // MARK: - Alert Mode Update Does Not Reschedule

    @MainActor
    func testUpdateCalendarAlertModes_doesNotReschedule() async {
        let event = TestUtilities.createTestEvent(
            startDate: fixedDate.addingTimeInterval(600),
            calendarId: "cal-1",
        )

        await eventScheduler.scheduleWithoutMonitoring(
            events: [event], overlayManager: overlayManager,
        )

        let alertsBefore = eventScheduler.scheduledAlerts.map(\.event.id)

        eventScheduler.updateCalendarAlertModes(["cal-1": .notification])

        let alertsAfter = eventScheduler.scheduledAlerts.map(\.event.id)
        XCTAssertEqual(alertsAfter, alertsBefore)
    }
}
