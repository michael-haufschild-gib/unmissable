@testable import Unmissable
import XCTest

@MainActor
final class PreferencesManagerTests: XCTestCase {
    var preferencesManager: PreferencesManager!

    override func setUp() async throws {
        // Clear UserDefaults for testing
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)

        preferencesManager = PreferencesManager()
    }

    override func tearDown() async throws {
        preferencesManager = nil
    }

    func testDefaultValues() {
        XCTAssertEqual(preferencesManager.defaultAlertMinutes, 1)
        XCTAssertFalse(preferencesManager.useLengthBasedTiming)
        XCTAssertEqual(preferencesManager.syncIntervalSeconds, 60)
        XCTAssertFalse(preferencesManager.includeAllDayEvents)
        XCTAssertEqual(preferencesManager.appearanceTheme, .system)
        XCTAssertEqual(preferencesManager.overlayOpacity, 0.9, accuracy: 0.001)
        XCTAssertEqual(preferencesManager.fontSize, .medium)
        XCTAssertTrue(preferencesManager.showOnAllDisplays)
        XCTAssertTrue(preferencesManager.playAlertSound)
        XCTAssertTrue(preferencesManager.overrideFocusMode)
    }

    func testAlertMinutesForEvent() {
        let shortEvent = Event(
            id: "short",
            title: "Short Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(15 * 60), // 15 minutes
            calendarId: "primary"
        )

        let mediumEvent = Event(
            id: "medium",
            title: "Medium Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(45 * 60), // 45 minutes
            calendarId: "primary"
        )

        let longEvent = Event(
            id: "long",
            title: "Long Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(90 * 60), // 90 minutes
            calendarId: "primary"
        )

        // Test default timing (not using length-based)
        XCTAssertEqual(preferencesManager.alertMinutes(for: shortEvent), 1)
        XCTAssertEqual(preferencesManager.alertMinutes(for: mediumEvent), 1)
        XCTAssertEqual(preferencesManager.alertMinutes(for: longEvent), 1)

        // Enable length-based timing
        preferencesManager.useLengthBasedTiming = true
        preferencesManager.shortMeetingAlertMinutes = 1
        preferencesManager.mediumMeetingAlertMinutes = 3
        preferencesManager.longMeetingAlertMinutes = 5

        XCTAssertEqual(preferencesManager.alertMinutes(for: shortEvent), 1)
        XCTAssertEqual(preferencesManager.alertMinutes(for: mediumEvent), 3)
        XCTAssertEqual(preferencesManager.alertMinutes(for: longEvent), 5)
    }

    func testPreferencePersistence() {
        // Change some preferences
        preferencesManager.defaultAlertMinutes = 5
        preferencesManager.useLengthBasedTiming = true
        preferencesManager.appearanceTheme = .dark
        preferencesManager.overlayOpacity = 0.7

        // Create new instance to test persistence
        let newPreferencesManager = PreferencesManager()

        XCTAssertEqual(newPreferencesManager.defaultAlertMinutes, 5)
        XCTAssertTrue(newPreferencesManager.useLengthBasedTiming)
        XCTAssertEqual(newPreferencesManager.appearanceTheme, .dark)
        XCTAssertEqual(newPreferencesManager.overlayOpacity, 0.7, accuracy: 0.001)
    }

    func testAppearanceThemeEnum() {
        XCTAssertEqual(AppTheme.system.displayName, "Follow System")
        XCTAssertEqual(AppTheme.light.displayName, "Light")
        XCTAssertEqual(AppTheme.dark.displayName, "Dark")

        let allThemes = AppTheme.allCases
        XCTAssertEqual(allThemes.count, 3)
    }

    func testFontSizeEnum() {
        XCTAssertEqual(FontSize.small.scale, 0.8, accuracy: 0.001)
        XCTAssertEqual(FontSize.medium.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(FontSize.large.scale, 1.4, accuracy: 0.001)

        let allSizes = FontSize.allCases
        XCTAssertEqual(allSizes.count, 3)
    }
}
