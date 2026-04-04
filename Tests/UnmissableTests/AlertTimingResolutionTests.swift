@testable import Unmissable
import XCTest

@MainActor
final class AlertTimingResolutionTests: XCTestCase {
    private var preferencesManager: PreferencesManager!

    override func setUp() async throws {
        try await super.setUp()
        let testDefaults = try XCTUnwrap(
            UserDefaults(suiteName: "test-\(UUID().uuidString)"),
        )
        preferencesManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
        )
    }

    override func tearDown() async throws {
        preferencesManager = nil
        try await super.tearDown()
    }

    func testAlertMinutes_withOverride_returnsOverride() {
        let event = Event(
            id: "test-1",
            title: "Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "cal-1",
        )

        let result = preferencesManager.alertMinutes(for: event, override: 10)
        XCTAssertEqual(result, 10, "Should return the override value")
    }

    func testAlertMinutes_withZeroOverride_returnsZero() {
        let event = Event(
            id: "test-1",
            title: "Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "cal-1",
        )

        let result = preferencesManager.alertMinutes(for: event, override: 0)
        XCTAssertEqual(result, 0, "Zero override means 'no alert'")
    }

    func testAlertMinutes_withNilOverride_fallsBackToDefault() {
        let event = Event(
            id: "test-1",
            title: "Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "cal-1",
        )

        let defaultMinutes = preferencesManager.defaultAlertMinutes
        let result = preferencesManager.alertMinutes(for: event, override: nil)
        XCTAssertEqual(
            result,
            defaultMinutes,
            "Nil override should fall back to default alert minutes",
        )
    }

    func testAlertMinutes_withNilOverride_usesLengthBasedTiming() {
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
        XCTAssertEqual(
            shortResult,
            1,
            "Short meeting should use short meeting alert minutes",
        )

        // Override takes precedence even when length-based is enabled
        let overrideResult = preferencesManager.alertMinutes(for: shortEvent, override: 15)
        XCTAssertEqual(
            overrideResult,
            15,
            "Override should take precedence over length-based timing",
        )
    }
}
