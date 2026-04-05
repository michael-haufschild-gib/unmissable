import Foundation
import Testing
@testable import Unmissable

@MainActor
struct AlertTimingResolutionTests {
    private var preferencesManager: PreferencesManager

    init() {
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        preferencesManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
        )
    }

    @Test
    func alertMinutes_withOverride_returnsOverride() {
        let event = Event(
            id: "test-1",
            title: "Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "cal-1",
        )

        let result = preferencesManager.alertMinutes(for: event, override: 10)
        #expect(result == 10, "Should return the override value")
    }

    @Test
    func alertMinutes_withZeroOverride_returnsZero() {
        let event = Event(
            id: "test-1",
            title: "Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "cal-1",
        )

        let result = preferencesManager.alertMinutes(for: event, override: 0)
        #expect(result == 0, "Zero override means 'no alert'")
    }

    @Test
    func alertMinutes_withNilOverride_fallsBackToDefault() {
        let event = Event(
            id: "test-1",
            title: "Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "cal-1",
        )

        let defaultMinutes = preferencesManager.defaultAlertMinutes
        let result = preferencesManager.alertMinutes(for: event, override: nil)
        #expect(
            result == defaultMinutes,
            "Nil override should fall back to default alert minutes",
        )
    }

    @Test
    func alertMinutes_withNilOverride_usesLengthBasedTiming() {
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setShortMeetingAlertMinutes(1)
        preferencesManager.setMediumMeetingAlertMinutes(3)
        preferencesManager.setLongMeetingAlertMinutes(7)

        // Short meeting (15 minutes)
        let shortEvent = Event(
            id: "short-1",
            title: "Quick Sync",
            startDate: Date(),
            endDate: Date().addingTimeInterval(900),
            calendarId: "cal-1",
        )

        let shortResult = preferencesManager.alertMinutes(for: shortEvent, override: nil)
        #expect(
            shortResult == 1,
            "Short meeting should use short meeting alert minutes",
        )

        // Override takes precedence even when length-based is enabled
        let overrideResult = preferencesManager.alertMinutes(for: shortEvent, override: 15)
        #expect(
            overrideResult == 15,
            "Override should take precedence over length-based timing",
        )
    }
}
