@testable import Unmissable
import XCTest

@MainActor
final class PreferencesManagerTests: XCTestCase {
    private var preferencesManager: PreferencesManager!
    private var testSuiteName: String!

    override func setUp() async throws {
        testSuiteName = "com.unmissable.test.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: testSuiteName)!
        preferencesManager = PreferencesManager(userDefaults: testDefaults, themeManager: ThemeManager())
        try await super.setUp()
    }

    override func tearDown() async throws {
        preferencesManager = nil
        if let suite = testSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        testSuiteName = nil
        try await super.tearDown()
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

    func testSyncIntervalSeconds_whenOutOfBounds_clampsToHardcodedBounds() {
        preferencesManager.setSyncIntervalSeconds(10) // below min (30)
        XCTAssertEqual(preferencesManager.syncIntervalSeconds, 30)

        preferencesManager.setSyncIntervalSeconds(5000) // above max (3600)
        XCTAssertEqual(preferencesManager.syncIntervalSeconds, 3600)
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
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setShortMeetingAlertMinutes(1)
        preferencesManager.setMediumMeetingAlertMinutes(3)
        preferencesManager.setLongMeetingAlertMinutes(5)

        XCTAssertEqual(preferencesManager.alertMinutes(for: shortEvent), 1)
        XCTAssertEqual(preferencesManager.alertMinutes(for: mediumEvent), 3)
        XCTAssertEqual(preferencesManager.alertMinutes(for: longEvent), 5)
    }

    func testPreferencePersistence() throws {
        // Change some preferences
        preferencesManager.setDefaultAlertMinutes(5)
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setAppearanceTheme(.dark)
        preferencesManager.setOverlayOpacity(0.7)

        // Create new instance backed by the same test suite to verify persistence
        let newPreferencesManager =
            try PreferencesManager(userDefaults: XCTUnwrap(UserDefaults(suiteName: testSuiteName)), themeManager: ThemeManager())

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
