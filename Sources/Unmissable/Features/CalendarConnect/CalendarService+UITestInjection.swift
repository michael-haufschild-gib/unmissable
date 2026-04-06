import Foundation
import OSLog

// MARK: - UI Test Event Injection

extension CalendarService {
    private enum TestEventTiming {
        static let event1StartMin = 45
        static let event1EndMin = 75
        static let event2StartMin = 60
        static let event2EndMin = 90
        static let event3StartHours = 2
        static let event3EndHours = 3
        static let event4StartMin = -3
        static let event4EndMin = 27
    }

    /// Populates synthetic events for osascript-based UI tests.
    /// Called when `--inject-test-events` launch argument is present.
    /// Bypasses real calendar backends entirely.
    func injectSyntheticEventsForUITesting() {
        let now = Date()
        let cal = Calendar.current
        guard let e1s = cal.date(byAdding: .minute, value: TestEventTiming.event1StartMin, to: now),
              let e1e = cal.date(byAdding: .minute, value: TestEventTiming.event1EndMin, to: now),
              let e2s = cal.date(byAdding: .minute, value: TestEventTiming.event2StartMin, to: now),
              let e2e = cal.date(byAdding: .minute, value: TestEventTiming.event2EndMin, to: now),
              let e3s = cal.date(byAdding: .hour, value: TestEventTiming.event3StartHours, to: now),
              let e3e = cal.date(byAdding: .hour, value: TestEventTiming.event3EndHours, to: now),
              let e4s = cal.date(byAdding: .minute, value: TestEventTiming.event4StartMin, to: now),
              let e4e = cal.date(byAdding: .minute, value: TestEventTiming.event4EndMin, to: now)
        else { return }

        let testLogger = Logger(category: "CalendarService.UITest")

        events = Self.buildTestEvents(e1s: e1s, e1e: e1e, e2s: e2s, e2e: e2e, e3s: e3s, e3e: e3e)
        startedEvents = Self.buildStartedTestEvents(e4s: e4s, e4e: e4e)
        calendars = [
            CalendarInfo(
                id: "ui-test-cal",
                name: "Work Calendar",
                isSelected: true,
                isPrimary: true,
                sourceProvider: .apple,
            ),
        ]
        isConnected = true
        connectedProviders = [.apple]
        syncStatus = .idle
        lastSyncTime = now
        usingSyntheticData = true
        testLogger.info("Injected \(self.events.count) synthetic events for UI testing")
    }

    // swiftlint:disable force_unwrapping
    private static func buildTestEvents(
        e1s: Date,
        e1e: Date,
        e2s: Date,
        e2e: Date,
        e3s: Date,
        e3e: Date,
    ) -> [Event] {
        [
            Event(
                id: "ui-test-1",
                title: "Team Standup",
                startDate: e1s,
                endDate: e1e,
                organizer: "manager@company.com",
                description: "Daily standup.",
                calendarId: "ui-test-cal",
                links: [URL(string: "https://meet.google.com/abc-defg-hij")!],
                provider: .meet,
            ),
            Event(
                id: "ui-test-2",
                title: "Design Review",
                startDate: e2s,
                endDate: e2e,
                organizer: "designer@company.com",
                calendarId: "ui-test-cal",
                links: [URL(string: "https://zoom.us/j/123456789")!],
                provider: .zoom,
            ),
            Event(
                id: "ui-test-3",
                title: "Lunch with Team",
                startDate: e3s,
                endDate: e3e,
                location: "Cafeteria B",
                calendarId: "ui-test-cal",
            ),
        ]
    }

    private static func buildStartedTestEvents(
        e4s: Date,
        e4e: Date,
    ) -> [Event] {
        [
            Event(
                id: "ui-test-4",
                title: "Sprint Planning",
                startDate: e4s,
                endDate: e4e,
                organizer: "pm@company.com",
                calendarId: "ui-test-cal",
                links: [URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!],
                provider: .teams,
            ),
        ]
    }
    // swiftlint:enable force_unwrapping
}
