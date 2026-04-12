import Foundation
import Testing
@testable import Unmissable

@MainActor
struct PreferencesManagerTests {
    private var preferencesManager: PreferencesManager
    private let testSuiteName: String
    private var testLoginItemManager: TestSafeLoginItemManager

    init() {
        testSuiteName = "com.unmissable.test.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: testSuiteName)!
        testLoginItemManager = TestSafeLoginItemManager()
        preferencesManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
            loginItemManager: testLoginItemManager,
        )
    }

    @Test
    func defaultValues() {
        #expect(preferencesManager.defaultAlertMinutes == 1)
        #expect(!preferencesManager.useLengthBasedTiming)
        #expect(preferencesManager.syncIntervalSeconds == 60)
        #expect(!preferencesManager.includeAllDayEvents)
        #expect(preferencesManager.themeMode == .system)
        #expect(abs(preferencesManager.overlayOpacity - 0.9) <= 0.001)
        #expect(preferencesManager.fontSize == .medium)
        #expect(preferencesManager.displaySelectionMode == .all)
        #expect(preferencesManager.playAlertSound)
        #expect(preferencesManager.launchAtLogin)
    }

    @Test
    func syncIntervalSeconds_whenOutOfBounds_clampsToHardcodedBounds() {
        preferencesManager.setSyncIntervalSeconds(10) // below min (30)
        #expect(preferencesManager.syncIntervalSeconds == 30)

        preferencesManager.setSyncIntervalSeconds(5000) // above max (3600)
        #expect(preferencesManager.syncIntervalSeconds == 3600)
    }

    @Test
    func alertMinutesForEvent() {
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
        #expect(preferencesManager.alertMinutes(for: shortEvent) == 1)
        #expect(preferencesManager.alertMinutes(for: mediumEvent) == 1)
        #expect(preferencesManager.alertMinutes(for: longEvent) == 1)

        // Enable length-based timing
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setShortMeetingAlertMinutes(1)
        preferencesManager.setMediumMeetingAlertMinutes(3)
        preferencesManager.setLongMeetingAlertMinutes(5)

        #expect(preferencesManager.alertMinutes(for: shortEvent) == 1)
        #expect(preferencesManager.alertMinutes(for: mediumEvent) == 3)
        #expect(preferencesManager.alertMinutes(for: longEvent) == 5)

        // Toggle length-based timing back off — all events should fall back to the default.
        // This covers the off→on→off direction that a user hits when they try LB and disable it.
        preferencesManager.setUseLengthBasedTiming(false)
        preferencesManager.setDefaultAlertMinutes(3)
        #expect(preferencesManager.alertMinutes(for: shortEvent) == 3, "LB off should revert to default for short")
        #expect(preferencesManager.alertMinutes(for: mediumEvent) == 3, "LB off should revert to default for medium")
        #expect(preferencesManager.alertMinutes(for: longEvent) == 3, "LB off should revert to default for long")
    }

    @Test
    func preferencePersistence() throws {
        // Change some preferences
        preferencesManager.setDefaultAlertMinutes(5)
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setThemeMode(.darkBlue)
        preferencesManager.setOverlayOpacity(0.7)

        // Create new instance backed by the same test suite to verify persistence
        let defaults = try #require(UserDefaults(suiteName: testSuiteName))
        let newPreferencesManager = PreferencesManager(
            userDefaults: defaults, themeManager: ThemeManager(),
        )

        #expect(newPreferencesManager.defaultAlertMinutes == 5)
        #expect(newPreferencesManager.useLengthBasedTiming)
        #expect(newPreferencesManager.themeMode == .darkBlue)
        #expect(abs(newPreferencesManager.overlayOpacity - 0.7) <= 0.001)
    }

    @Test
    func themeModeEnum() {
        #expect(ThemeMode.system.displayName == "System")
        #expect(ThemeMode.light.displayName == "Light")
        #expect(ThemeMode.darkBlue.displayName == "Dark Blue")

        let allThemes = ThemeMode.allCases
        #expect(
            allThemes == [.system, .light, .darkBlue, .darkPurple, .darkBrown, .darkBlack],
        )
    }

    // MARK: - Boundary Clamping Tests

    @Test
    func overlayOpacity_clampedToValidRange() {
        preferencesManager.setOverlayOpacity(0.0) // below min (0.1)
        #expect(abs(preferencesManager.overlayOpacity - 0.1) <= 0.001)

        preferencesManager.setOverlayOpacity(2.0) // above max (1.0)
        #expect(abs(preferencesManager.overlayOpacity - 1.0) <= 0.001)

        preferencesManager.setOverlayOpacity(0.5) // valid
        #expect(abs(preferencesManager.overlayOpacity - 0.5) <= 0.001)
    }

    @Test
    func overlayOpacity_exactBoundaryValues() {
        preferencesManager.setOverlayOpacity(0.1) // min
        #expect(abs(preferencesManager.overlayOpacity - 0.1) <= 0.001)

        preferencesManager.setOverlayOpacity(1.0) // max
        #expect(abs(preferencesManager.overlayOpacity - 1.0) <= 0.001)
    }

    @Test
    func defaultAlertMinutes_clampedToValidRange() {
        preferencesManager.setDefaultAlertMinutes(-5)
        #expect(preferencesManager.defaultAlertMinutes == 0, "Negative values should clamp to 0")

        preferencesManager.setDefaultAlertMinutes(100)
        #expect(preferencesManager.defaultAlertMinutes == 60, "Values above 60 should clamp to 60")

        preferencesManager.setDefaultAlertMinutes(30) // valid
        #expect(preferencesManager.defaultAlertMinutes == 30)
    }

    @Test
    func shortMeetingAlertMinutes_clampedToValidRange() {
        preferencesManager.setShortMeetingAlertMinutes(-1)
        #expect(preferencesManager.shortMeetingAlertMinutes == 0)

        preferencesManager.setShortMeetingAlertMinutes(61)
        #expect(preferencesManager.shortMeetingAlertMinutes == 60)
    }

    @Test
    func mediumMeetingAlertMinutes_clampedToValidRange() {
        preferencesManager.setMediumMeetingAlertMinutes(-1)
        #expect(preferencesManager.mediumMeetingAlertMinutes == 0)

        preferencesManager.setMediumMeetingAlertMinutes(100)
        #expect(preferencesManager.mediumMeetingAlertMinutes == 60)
    }

    @Test
    func longMeetingAlertMinutes_clampedToValidRange() {
        preferencesManager.setLongMeetingAlertMinutes(-1)
        #expect(preferencesManager.longMeetingAlertMinutes == 0)

        preferencesManager.setLongMeetingAlertMinutes(100)
        #expect(preferencesManager.longMeetingAlertMinutes == 60)
    }

    @Test
    func syncInterval_exactBoundaryValues() {
        preferencesManager.setSyncIntervalSeconds(30) // min
        #expect(preferencesManager.syncIntervalSeconds == 30)

        preferencesManager.setSyncIntervalSeconds(3600) // max
        #expect(preferencesManager.syncIntervalSeconds == 3600)
    }

    // MARK: - MenuBarDisplayMode

    @Test
    func menuBarDisplayMode_defaultIsIcon() {
        #expect(preferencesManager.menuBarDisplayMode == .icon)
    }

    @Test
    func menuBarDisplayMode_persistsAcrossInstances() throws {
        preferencesManager.setMenuBarDisplayMode(.nameTimer)

        let defaults = try #require(UserDefaults(suiteName: testSuiteName))
        let newPreferencesManager = PreferencesManager(
            userDefaults: defaults, themeManager: ThemeManager(),
        )

        #expect(newPreferencesManager.menuBarDisplayMode == .nameTimer)
    }

    @Test
    func menuBarDisplayModeEnum() {
        #expect(
            MenuBarDisplayMode.allCases == [.icon, .timer, .nameTimer],
            "MenuBarDisplayMode should have exactly icon, timer, nameTimer in order",
        )
    }

    // MARK: - Alert Minutes for Event (Length-Based Boundary)

    @Test
    func alertMinutesForEvent_exactly29Minutes_usesShort() {
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
        #expect(preferencesManager.alertMinutes(for: event) == 1, "29 min < 30 = short")
    }

    @Test
    func alertMinutesForEvent_exactly30Minutes_usesMedium() {
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
        #expect(preferencesManager.alertMinutes(for: event) == 3, "30 min >= 30 = medium")
    }

    @Test
    func alertMinutesForEvent_exactly60Minutes_usesMedium() {
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
        #expect(preferencesManager.alertMinutes(for: event) == 3, "60 min <= 60 = medium")
    }

    @Test
    func alertMinutesForEvent_exactly61Minutes_usesLong() {
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
        #expect(preferencesManager.alertMinutes(for: event) == 5, "61 min > 60 = long")
    }

    @Test
    func alertMinutesForEvent_zeroDuration_usesShort() {
        preferencesManager.setUseLengthBasedTiming(true)
        preferencesManager.setShortMeetingAlertMinutes(1)

        let event = Event(
            id: "zero-dur",
            title: "Zero Duration",
            startDate: Date(),
            endDate: Date(), // same time
            calendarId: "primary",
        )
        #expect(preferencesManager.alertMinutes(for: event) == 1, "Zero duration < 30 = short")
    }

    @Test
    func fontSizeEnum() {
        #expect(abs(FontSize.small.scale - 0.8) <= 0.001)
        #expect(abs(FontSize.medium.scale - 1.0) <= 0.001)
        #expect(abs(FontSize.large.scale - 1.4) <= 0.001)

        let allSizes = FontSize.allCases
        #expect(allSizes == [.small, .medium, .large])
    }

    // MARK: - Launch at Login

    @Test
    func launchAtLogin_defaultsToTrue() {
        #expect(
            preferencesManager.launchAtLogin,
            "Launch at login should default to true on first launch",
        )
    }

    @Test
    func setLaunchAtLogin_updatesPropertyAndCallsLoginItemManager() {
        // Init registers as login item (first launch), so history starts with [true].
        let historyBefore = testLoginItemManager.registrationHistory

        preferencesManager.setLaunchAtLogin(false)
        #expect(!preferencesManager.launchAtLogin)

        preferencesManager.setLaunchAtLogin(true)
        #expect(preferencesManager.launchAtLogin)

        // Full history: initial registration + disable + re-enable
        #expect(testLoginItemManager.registrationHistory == historyBefore + [false, true])
    }

    @Test
    func launchAtLogin_persistsAcrossInstances() throws {
        let loginManager = TestSafeLoginItemManager()
        preferencesManager.setLaunchAtLogin(false)

        let defaults = try #require(UserDefaults(suiteName: testSuiteName))
        let newManager = PreferencesManager(
            userDefaults: defaults,
            themeManager: ThemeManager(),
            loginItemManager: loginManager,
        )

        #expect(
            !newManager.launchAtLogin,
            "Launch at login should persist false across instances",
        )
        // Should NOT have called updateRegistration since key already exists
        #expect(loginManager.registrationHistory.isEmpty)
    }

    @Test
    func launchAtLogin_firstLaunch_registersAndPersists() throws {
        // preferencesManager was created with fresh UserDefaults (no prior keys).
        // loadPreferences should have detected first launch, called register, and written the key.
        let defaults = try #require(UserDefaults(suiteName: testSuiteName))
        let storedValue = try #require(defaults.object(forKey: "launchAtLogin") as? Bool)
        #expect(storedValue, "First launch should persist launchAtLogin=true")
        #expect(testLoginItemManager.registrationHistory == [true])
    }

    @Test
    func syncLoginItemWithSystem_systemEnabled_updatesPreference() {
        // User disabled in-app, then enabled via System Settings
        preferencesManager.setLaunchAtLogin(false)
        testLoginItemManager.stubbedIsRegistered = true

        preferencesManager.syncLoginItemWithSystem()

        #expect(
            preferencesManager.launchAtLogin,
            "Should sync preference to true when system reports enabled",
        )
    }

    @Test
    func syncLoginItemWithSystem_systemDisabled_doesNotOverridePreference() {
        // User has preference ON, but system reports not-registered (dev/unsigned build)
        testLoginItemManager.stubbedIsRegistered = false

        preferencesManager.syncLoginItemWithSystem()

        #expect(
            preferencesManager.launchAtLogin,
            "Should NOT override preference when system reports not-registered",
        )
    }

    // MARK: - Display Selection

    @Test
    func displaySelectionMode_defaultIsAll() {
        #expect(preferencesManager.displaySelectionMode == .all)
        #expect(preferencesManager.selectedDisplayKeys.isEmpty)
    }

    @Test
    func displaySelectionMode_persistsAcrossInstances() throws {
        preferencesManager.setDisplaySelectionMode(.externalOnly)

        let defaults = try #require(UserDefaults(suiteName: testSuiteName))
        let newManager = PreferencesManager(
            userDefaults: defaults, themeManager: ThemeManager(),
        )
        #expect(newManager.displaySelectionMode == .externalOnly)
    }

    @Test
    func selectedDisplayKeys_persistsAcrossInstances() throws {
        preferencesManager.setSelectedDisplayKeys(["1715-10092-100", "1552-41054-200"])

        let defaults = try #require(UserDefaults(suiteName: testSuiteName))
        let newManager = PreferencesManager(
            userDefaults: defaults, themeManager: ThemeManager(),
        )
        #expect(newManager.selectedDisplayKeys == ["1715-10092-100", "1552-41054-200"])
    }

    @Test
    func toggleDisplay_addsAndRemovesKey() {
        let key = "1715-10092-100"
        preferencesManager.toggleDisplay(key: key)
        #expect(preferencesManager.selectedDisplayKeys.contains(key))

        preferencesManager.toggleDisplay(key: key)
        #expect(!preferencesManager.selectedDisplayKeys.contains(key))
    }

    @Test
    func displaySelectionMode_legacyMigration_allDisplaysTrue() throws {
        // Write legacy boolean, no new key
        let defaults = try #require(UserDefaults(suiteName: testSuiteName))
        defaults.removeObject(forKey: "displaySelectionMode")
        defaults.set(true, forKey: "showOnAllDisplays")

        let newManager = PreferencesManager(
            userDefaults: defaults, themeManager: ThemeManager(),
        )
        #expect(
            newManager.displaySelectionMode == .all,
            "Legacy showOnAllDisplays=true should migrate to .all",
        )
    }

    @Test
    func displaySelectionMode_legacyMigration_allDisplaysFalse() throws {
        let defaults = try #require(UserDefaults(suiteName: testSuiteName))
        defaults.removeObject(forKey: "displaySelectionMode")
        defaults.set(false, forKey: "showOnAllDisplays")

        let newManager = PreferencesManager(
            userDefaults: defaults, themeManager: ThemeManager(),
        )
        #expect(
            newManager.displaySelectionMode == .mainOnly,
            "Legacy showOnAllDisplays=false should migrate to .mainOnly",
        )
    }

    @Test
    func showOnAllDisplays_legacyAccessor_matchesMode() {
        preferencesManager.setDisplaySelectionMode(.all)
        #expect(preferencesManager.showOnAllDisplays)

        preferencesManager.setDisplaySelectionMode(.externalOnly)
        #expect(!preferencesManager.showOnAllDisplays)

        preferencesManager.setDisplaySelectionMode(.mainOnly)
        #expect(!preferencesManager.showOnAllDisplays)
    }

    @Test
    func displaySelectionModeEnum_allCases() {
        #expect(
            DisplaySelectionMode.allCases == [.all, .mainOnly, .externalOnly, .selected],
            "DisplaySelectionMode should have exactly 4 cases in order",
        )
    }
}
