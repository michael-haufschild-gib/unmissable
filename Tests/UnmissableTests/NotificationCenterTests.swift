import Foundation
import Testing
@testable import Unmissable

// MARK: - Notification Center Alert Mode Tests

@MainActor
struct NotificationCenterTests {
    private var eventScheduler: EventScheduler
    private var mockPreferences: PreferencesManager
    private var overlayManager: TestSafeOverlayManager
    private var notificationManager: TestSafeNotificationManager
    /// Fixed reference time for deterministic scheduling.
    private var fixedDate: Date

    init() {
        fixedDate = Date()
        mockPreferences = TestUtilities.createTestPreferencesManager()
        mockPreferences.testOverlayShowMinutesBefore = 2
        let capturedDate = fixedDate
        eventScheduler = EventScheduler(
            preferencesManager: mockPreferences,
            linkParser: LinkParser(),
            now: { capturedDate },
        )
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        notificationManager = TestSafeNotificationManager()
        eventScheduler.setNotificationManager(notificationManager)
    }

    // MARK: - AlertMode Enum

    @Test
    func alertMode_rawValueRoundTrip() {
        for mode in AlertMode.allCases {
            let decoded = AlertMode(rawValue: mode.rawValue)
            #expect(decoded == mode, "Round-trip failed for \(mode)")
        }
    }

    @Test
    func alertMode_displayNames() {
        #expect(AlertMode.overlay.displayName == "Full-Screen Overlay")
        #expect(AlertMode.notification.displayName == "Notification")
        #expect(AlertMode.none.displayName == "None")
    }

    @Test
    func alertMode_rawValues() {
        #expect(AlertMode.overlay.rawValue == "overlay")
        #expect(AlertMode.notification.rawValue == "notification")
        #expect(AlertMode.none.rawValue == "none")
    }

    // MARK: - CalendarInfo AlertMode

    @Test
    func calendarInfo_defaultAlertModeIsOverlay() {
        let calendar = CalendarInfo(id: "cal-1", name: "Work")
        #expect(calendar.alertMode == .overlay)
    }

    @Test
    func calendarInfo_withAlertModePreservesOtherFields() {
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

        #expect(updated.id == "cal-1")
        #expect(updated.name == "Work")
        #expect(updated.isSelected)
        #expect(updated.isPrimary)
        #expect(updated.colorHex == "#FF0000")
        #expect(updated.sourceProvider == .google)
        #expect(updated.alertMode == .notification)
    }

    @Test
    func calendarInfo_withSelectionPreservesAlertMode() {
        let calendar = CalendarInfo(
            id: "cal-1",
            name: "Work",
            isSelected: false,
            alertMode: .notification,
        )

        let updated = calendar.withSelection(true)

        #expect(updated.isSelected)
        #expect(updated.alertMode == .notification)
    }

    // MARK: - Overlay Mode (Default)

    @Test
    func defaultAlertMode_usesOverlay() async {
        let event = TestUtilities.createTestEvent(
            startDate: fixedDate.addingTimeInterval(60),
            calendarId: "cal-1",
        )

        // Alert fires at 5 min before, event is 1 min away → missed, triggers immediately
        mockPreferences.testOverlayShowMinutesBefore = 5
        await eventScheduler.scheduleWithoutMonitoring(
            events: [event], overlayManager: overlayManager,
        )

        #expect(overlayManager.isOverlayVisible, "Default mode should show overlay")
        #expect(overlayManager.activeEvent?.id == event.id)
        #expect(notificationManager.sentNotifications.map(\.event.id).isEmpty)
    }

    // MARK: - Notification Mode

    @Test
    func notificationMode_sendsNotificationNotOverlay() async throws {
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

        #expect(!overlayManager.isOverlayVisible, "Notification mode should NOT show overlay")

        // Wait for the async Task that sends the notification
        let notifMgr = notificationManager
        try await TestUtilities.waitForAsync {
            await MainActor.run { notifMgr.sentNotifications.count == 1 }
        }

        #expect(notificationManager.sentNotifications.first?.event.id == "evt-notif")
    }

    // MARK: - None Mode

    @Test
    func noneMode_suppressesAllAlerts() async throws {
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

        #expect(!overlayManager.isOverlayVisible)
        #expect(notificationManager.sentNotifications.map(\.event.id).isEmpty)
    }

    // MARK: - Snooze Always Uses Overlay

    @Test
    func snooze_alwaysUsesOverlay_regardlessOfCalendarMode() async {
        eventScheduler.updateCalendarAlertModes(["cal-notif": .notification])

        let event = TestUtilities.createTestEvent(
            id: "snooze-evt",
            startDate: fixedDate.addingTimeInterval(300),
            calendarId: "cal-notif",
        )

        await eventScheduler.scheduleWithoutMonitoring(
            events: [event], overlayManager: overlayManager,
        )

        #expect(!overlayManager.isOverlayVisible)

        eventScheduler.scheduleSnooze(for: event, minutes: 1)

        let snoozeAlerts = eventScheduler.scheduledAlerts.filter {
            if case .snooze = $0.alertType { return true }
            return false
        }
        // Verify both presence and identity of the snooze alert
        #expect(snoozeAlerts.first?.event.id == "snooze-evt")
        #expect(snoozeAlerts.first?.event.calendarId == "cal-notif")
    }

    // MARK: - Mixed Calendars

    @Test
    func mixedModes_routeCorrectly() async throws {
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
        let notifMgr = notificationManager
        try await TestUtilities.waitForAsync {
            await MainActor.run { notifMgr.sentNotifications.count == 1 }
        }

        // Overlay event should have triggered overlay
        #expect(overlayManager.isOverlayVisible)

        // Notification event should have sent exactly one notification
        #expect(notificationManager.sentNotifications.first?.event.id == "evt-notif")
        // Verify no extra notifications from overlay or silent events
        let notifEventIds = notificationManager.sentNotifications.map(\.event.id)
        #expect(notifEventIds == ["evt-notif"])
    }

    // MARK: - Unknown Calendar Defaults to Overlay

    @Test
    func unknownCalendar_defaultsToOverlay() async {
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

        #expect(overlayManager.isOverlayVisible)
        #expect(overlayManager.activeEvent?.id == "unknown-evt")
    }

    // MARK: - Alert Mode Update Does Not Reschedule

    @Test
    func updateCalendarAlertModes_doesNotReschedule() async {
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
        #expect(alertsAfter == alertsBefore)
    }
}
