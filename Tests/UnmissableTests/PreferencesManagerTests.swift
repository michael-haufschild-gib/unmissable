@testable import Unmissable
import XCTest

@MainActor
final class PreferencesManagerTests: XCTestCase {
    private var preferencesManager: PreferencesManager!
    private var testSuiteName: String!
    private var testLoginItemManager: TestSafeLoginItemManager!

    override func setUp() async throws {
        testSuiteName = "com.unmissable.test.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: testSuiteName)!
        testLoginItemManager = TestSafeLoginItemManager()
        preferencesManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
            loginItemManager: testLoginItemManager,
        )
        try await super.setUp()
    }

    override func tearDown() async throws {
        preferencesManager = nil
        testLoginItemManager = nil
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
        XCTAssertEqual(preferencesManager.themeMode, .system)
        XCTAssertEqual(preferencesManager.overlayOpacity, 0.9, accuracy: 0.001)
        XCTAssertEqual(preferencesManager.fontSize, .medium)
        XCTAssertTrue(preferencesManager.showOnAllDisplays)
        XCTAssertTrue(preferencesManager.playAlertSound)
        XCTAssertTrue(preferencesManager.overrideFocusMode)
        XCTAssertTrue(preferencesManager.launchAtLogin)
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
            calendarId: "primary",
        )

        let mediumEvent = Event(
            id: "medium",
            title: "Medium Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(45 * 60), // 45 minutes
            calendarId: "primary",
        )

        let longEvent = Event(
            id: "long",
            title: "Long Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(90 * 60), // 90 minutes
            calendarId: "primary",
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
        preferencesManager.setThemeMode(.darkBlue)
        preferencesManager.setOverlayOpacity(0.7)

        // Create new instance backed by the same test suite to verify persistence
        let defaults = try XCTUnwrap(UserDefaults(suiteName: testSuiteName))
        let newPreferencesManager = PreferencesManager(
            userDefaults: defaults, themeManager: ThemeManager(),
        )

        XCTAssertEqual(newPreferencesManager.defaultAlertMinutes, 5)
        XCTAssertTrue(newPreferencesManager.useLengthBasedTiming)
        XCTAssertEqual(newPreferencesManager.themeMode, .darkBlue)
        XCTAssertEqual(newPreferencesManager.overlayOpacity, 0.7, accuracy: 0.001)
    }

    func testThemeModeEnum() {
        XCTAssertEqual(ThemeMode.system.displayName, "System")
        XCTAssertEqual(ThemeMode.light.displayName, "Light")
        XCTAssertEqual(ThemeMode.darkBlue.displayName, "Dark Blue")

        let allThemes = ThemeMode.allCases
        XCTAssertEqual(
            allThemes,
            [.system, .light, .darkBlue, .darkPurple, .darkBrown, .darkBlack],
        )
    }

    // MARK: - Boundary Clamping Tests

    func testOverlayOpacity_clampedToValidRange() {
        preferencesManager.setOverlayOpacity(0.0) // below min (0.1)
        XCTAssertEqual(preferencesManager.overlayOpacity, 0.1, accuracy: 0.001)

        preferencesManager.setOverlayOpacity(2.0) // above max (1.0)
        XCTAssertEqual(preferencesManager.overlayOpacity, 1.0, accuracy: 0.001)

        preferencesManager.setOverlayOpacity(0.5) // valid
        XCTAssertEqual(preferencesManager.overlayOpacity, 0.5, accuracy: 0.001)
    }

    func testOverlayOpacity_exactBoundaryValues() {
        preferencesManager.setOverlayOpacity(0.1) // min
        XCTAssertEqual(preferencesManager.overlayOpacity, 0.1, accuracy: 0.001)

        preferencesManager.setOverlayOpacity(1.0) // max
        XCTAssertEqual(preferencesManager.overlayOpacity, 1.0, accuracy: 0.001)
    }

    func testDefaultAlertMinutes_clampedToValidRange() {
        preferencesManager.setDefaultAlertMinutes(-5)
        XCTAssertEqual(preferencesManager.defaultAlertMinutes, 0, "Negative values should clamp to 0")

        preferencesManager.setDefaultAlertMinutes(100)
        XCTAssertEqual(preferencesManager.defaultAlertMinutes, 60, "Values above 60 should clamp to 60")

        preferencesManager.setDefaultAlertMinutes(30) // valid
        XCTAssertEqual(preferencesManager.defaultAlertMinutes, 30)
    }

    func testShortMeetingAlertMinutes_clampedToValidRange() {
        preferencesManager.setShortMeetingAlertMinutes(-1)
        XCTAssertEqual(preferencesManager.shortMeetingAlertMinutes, 0)

        preferencesManager.setShortMeetingAlertMinutes(61)
        XCTAssertEqual(preferencesManager.shortMeetingAlertMinutes, 60)
    }

    func testMediumMeetingAlertMinutes_clampedToValidRange() {
        preferencesManager.setMediumMeetingAlertMinutes(-1)
        XCTAssertEqual(preferencesManager.mediumMeetingAlertMinutes, 0)

        preferencesManager.setMediumMeetingAlertMinutes(100)
        XCTAssertEqual(preferencesManager.mediumMeetingAlertMinutes, 60)
    }

    func testLongMeetingAlertMinutes_clampedToValidRange() {
        preferencesManager.setLongMeetingAlertMinutes(-1)
        XCTAssertEqual(preferencesManager.longMeetingAlertMinutes, 0)

        preferencesManager.setLongMeetingAlertMinutes(100)
        XCTAssertEqual(preferencesManager.longMeetingAlertMinutes, 60)
    }

    func testSyncInterval_exactBoundaryValues() {
        preferencesManager.setSyncIntervalSeconds(30) // min
        XCTAssertEqual(preferencesManager.syncIntervalSeconds, 30)

        preferencesManager.setSyncIntervalSeconds(3600) // max
        XCTAssertEqual(preferencesManager.syncIntervalSeconds, 3600)
    }

    // MARK: - MenuBarDisplayMode

    func testMenuBarDisplayMode_defaultIsIcon() {
        XCTAssertEqual(preferencesManager.menuBarDisplayMode, .icon)
    }

    func testMenuBarDisplayMode_persistsAcrossInstances() throws {
        preferencesManager.setMenuBarDisplayMode(.nameTimer)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: testSuiteName))
        let newPreferencesManager = PreferencesManager(
            userDefaults: defaults, themeManager: ThemeManager(),
        )

        XCTAssertEqual(newPreferencesManager.menuBarDisplayMode, .nameTimer)
    }

    func testMenuBarDisplayModeEnum() {
        XCTAssertEqual(
            MenuBarDisplayMode.allCases,
            [.icon, .timer, .nameTimer],
            "MenuBarDisplayMode should have exactly icon, timer, nameTimer in order",
        )
    }

    // MARK: - Alert Minutes for Event (Length-Based Boundary)

    func testAlertMinutesForEvent_exactly29Minutes_usesShort() {
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setShortMeetingAlertMinutes(1)
        preferencesManager.setMediumMeetingAlertMinutes(3)
        preferencesManager.setLongMeetingAlertMinutes(5)

        let event = Event(
            id: "boundary-29",
            title: "29 Min Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(29 * 60),
            calendarId: "primary",
        )
        XCTAssertEqual(preferencesManager.alertMinutes(for: event), 1, "29 min < 30 = short")
    }

    func testAlertMinutesForEvent_exactly30Minutes_usesMedium() {
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setShortMeetingAlertMinutes(1)
        preferencesManager.setMediumMeetingAlertMinutes(3)

        let event = Event(
            id: "boundary-30",
            title: "30 Min Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(30 * 60),
            calendarId: "primary",
        )
        XCTAssertEqual(preferencesManager.alertMinutes(for: event), 3, "30 min >= 30 = medium")
    }

    func testAlertMinutesForEvent_exactly60Minutes_usesMedium() {
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setMediumMeetingAlertMinutes(3)
        preferencesManager.setLongMeetingAlertMinutes(5)

        let event = Event(
            id: "boundary-60",
            title: "60 Min Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(60 * 60),
            calendarId: "primary",
        )
        XCTAssertEqual(preferencesManager.alertMinutes(for: event), 3, "60 min <= 60 = medium")
    }

    func testAlertMinutesForEvent_exactly61Minutes_usesLong() {
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setMediumMeetingAlertMinutes(3)
        preferencesManager.setLongMeetingAlertMinutes(5)

        let event = Event(
            id: "boundary-61",
            title: "61 Min Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(61 * 60),
            calendarId: "primary",
        )
        XCTAssertEqual(preferencesManager.alertMinutes(for: event), 5, "61 min > 60 = long")
    }

    func testAlertMinutesForEvent_zeroDuration_usesShort() {
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setShortMeetingAlertMinutes(1)

        let event = Event(
            id: "zero-dur",
            title: "Zero Duration",
            startDate: Date(),
            endDate: Date(), // same time
            calendarId: "primary",
        )
        XCTAssertEqual(preferencesManager.alertMinutes(for: event), 1, "Zero duration < 30 = short")
    }

    func testFontSizeEnum() {
        XCTAssertEqual(FontSize.small.scale, 0.8, accuracy: 0.001)
        XCTAssertEqual(FontSize.medium.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(FontSize.large.scale, 1.4, accuracy: 0.001)

        let allSizes = FontSize.allCases
        XCTAssertEqual(allSizes, [.small, .medium, .large])
    }

    // MARK: - Launch at Login

    func testLaunchAtLogin_defaultsToTrue() {
        XCTAssertTrue(
            preferencesManager.launchAtLogin,
            "Launch at login should default to true on first launch",
        )
    }

    func testSetLaunchAtLogin_updatesPropertyAndCallsLoginItemManager() {
        // Init registers as login item (first launch), so history starts with [true].
        let historyBefore = testLoginItemManager.registrationHistory

        preferencesManager.setLaunchAtLogin(false)
        XCTAssertFalse(preferencesManager.launchAtLogin)

        preferencesManager.setLaunchAtLogin(true)
        XCTAssertTrue(preferencesManager.launchAtLogin)

        // Full history: initial registration + disable + re-enable
        XCTAssertEqual(testLoginItemManager.registrationHistory, historyBefore + [false, true])
    }

    func testLaunchAtLogin_persistsAcrossInstances() throws {
        let loginManager = TestSafeLoginItemManager()
        preferencesManager.setLaunchAtLogin(false)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: testSuiteName))
        let newManager = PreferencesManager(
            userDefaults: defaults,
            themeManager: ThemeManager(),
            loginItemManager: loginManager,
        )

        XCTAssertFalse(
            newManager.launchAtLogin,
            "Launch at login should persist false across instances",
        )
        // Should NOT have called updateRegistration since key already exists
        XCTAssertEqual(loginManager.registrationHistory, [])
    }

    func testLaunchAtLogin_firstLaunch_registersAndPersists() throws {
        // preferencesManager was created with fresh UserDefaults (no prior keys).
        // loadPreferences should have detected first launch, called register, and written the key.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: testSuiteName))
        let storedValue = try XCTUnwrap(defaults.object(forKey: "launchAtLogin") as? Bool)
        XCTAssertTrue(storedValue, "First launch should persist launchAtLogin=true")
        XCTAssertEqual(testLoginItemManager.registrationHistory, [true])
    }

    func testSyncLoginItemWithSystem_systemEnabled_updatesPreference() {
        // User disabled in-app, then enabled via System Settings
        preferencesManager.setLaunchAtLogin(false)
        testLoginItemManager.stubbedIsRegistered = true

        preferencesManager.syncLoginItemWithSystem()

        XCTAssertTrue(
            preferencesManager.launchAtLogin,
            "Should sync preference to true when system reports enabled",
        )
    }

    func testSyncLoginItemWithSystem_systemDisabled_doesNotOverridePreference() {
        // User has preference ON, but system reports not-registered (dev/unsigned build)
        testLoginItemManager.stubbedIsRegistered = false

        preferencesManager.syncLoginItemWithSystem()

        XCTAssertTrue(
            preferencesManager.launchAtLogin,
            "Should NOT override preference when system reports not-registered",
        )
    }
}
