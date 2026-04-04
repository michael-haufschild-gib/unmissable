import Combine
import Foundation
import SwiftUI

// MARK: - Type-safe UserDefaults Keys

private enum PrefKey: String {
    case defaultAlertMinutes
    case useLengthBasedTiming
    case shortMeetingAlertMinutes
    case mediumMeetingAlertMinutes
    case longMeetingAlertMinutes
    case syncIntervalSeconds
    case includeAllDayEvents
    case themeMode
    case accentColor
    case overlayOpacity
    case overlayShowMinutesBefore
    case fontSize
    case minimalMode
    case showOnAllDisplays
    case playAlertSound
    case alertVolume
    case overrideFocusMode
    case autoJoinEnabled
    case allowSnooze
    case menuBarDisplayMode
    case showTodayOnlyInMenuBar
    case launchAtLogin
    case smartSuppression
    case hasCompletedOnboarding
}

private extension UserDefaults {
    func set(_ value: Any?, forKey key: PrefKey) {
        set(value, forKey: key.rawValue)
    }

    func object(forKey key: PrefKey) -> Any? {
        object(forKey: key.rawValue)
    }

    func bool(forKey key: PrefKey) -> Bool {
        bool(forKey: key.rawValue)
    }
}

@MainActor
final class PreferencesManager: ObservableObject {
    private let userDefaults: UserDefaults
    private let themeManager: ThemeManager
    private let loginItemManager: any LoginItemManaging

    // MARK: - Default Values

    private static let defaultAlertMinutesDefault = 1
    private static let shortMeetingAlertDefault = 1
    private static let mediumMeetingAlertDefault = 2
    private static let longMeetingAlertDefault = 5
    private static let alertMinutesRange = 0 ... 60
    private static let syncIntervalDefault = 60
    private static let syncIntervalRange = 30 ... 3600
    private static let overlayOpacityDefault: Double = 0.9
    private static let overlayOpacityRange: ClosedRange<Double> = 0.1 ... 1.0
    private static let overlayShowMinutesDefault = 5
    private static let overlayShowMinutesRange = 0 ... 60
    private static let alertVolumeDefault: Double = 0.7
    private static let alertVolumeRange: ClosedRange<Double> = 0.0 ... 1.0
    private static let shortMeetingThresholdMinutes = 30
    private static let longMeetingThresholdMinutes = 60
    private static let secondsPerMinute = 60

    // MARK: - Properties

    // All properties use `private(set)` with explicit setter methods that persist to
    // UserDefaults. This eliminates the fragile `didSet`/`isLoading` guard pattern.
    // `loadPreferences()` assigns directly to the backing stores without triggering persistence.

    /// Alert timing (validated to 0-60 minutes)
    @Published
    private(set) var defaultAlertMinutes: Int = defaultAlertMinutesDefault
    func setDefaultAlertMinutes(_ value: Int) {
        defaultAlertMinutes = Self.clamp(value, to: Self.alertMinutesRange)
        userDefaults.set(defaultAlertMinutes, forKey: PrefKey.defaultAlertMinutes)
    }

    @Published
    private(set) var useLengthBasedTiming: Bool = false
    func setUseLengthBasedTiming(_ value: Bool) {
        useLengthBasedTiming = value
        userDefaults.set(value, forKey: PrefKey.useLengthBasedTiming)
    }

    @Published
    private(set) var shortMeetingAlertMinutes: Int = shortMeetingAlertDefault
    func setShortMeetingAlertMinutes(_ value: Int) {
        shortMeetingAlertMinutes = Self.clamp(value, to: Self.alertMinutesRange)
        userDefaults.set(shortMeetingAlertMinutes, forKey: PrefKey.shortMeetingAlertMinutes)
    }

    @Published
    private(set) var mediumMeetingAlertMinutes: Int = mediumMeetingAlertDefault
    func setMediumMeetingAlertMinutes(_ value: Int) {
        mediumMeetingAlertMinutes = Self.clamp(value, to: Self.alertMinutesRange)
        userDefaults.set(mediumMeetingAlertMinutes, forKey: PrefKey.mediumMeetingAlertMinutes)
    }

    @Published
    private(set) var longMeetingAlertMinutes: Int = longMeetingAlertDefault
    func setLongMeetingAlertMinutes(_ value: Int) {
        longMeetingAlertMinutes = Self.clamp(value, to: Self.alertMinutesRange)
        userDefaults.set(longMeetingAlertMinutes, forKey: PrefKey.longMeetingAlertMinutes)
    }

    /// Sync settings (validated to 30-3600 seconds)
    @Published
    private(set) var syncIntervalSeconds: Int = syncIntervalDefault
    func setSyncIntervalSeconds(_ value: Int) {
        syncIntervalSeconds = Self.clamp(value, to: Self.syncIntervalRange)
        userDefaults.set(syncIntervalSeconds, forKey: PrefKey.syncIntervalSeconds)
    }

    @Published
    private(set) var includeAllDayEvents: Bool = false
    func setIncludeAllDayEvents(_ value: Bool) {
        includeAllDayEvents = value
        userDefaults.set(value, forKey: PrefKey.includeAllDayEvents)
    }

    /// Theme mode
    @Published
    private(set) var themeMode: ThemeMode = .system
    func setThemeMode(_ value: ThemeMode) {
        themeMode = value
        userDefaults.set(value.rawValue, forKey: PrefKey.themeMode)
        themeManager.setTheme(value)
    }

    /// Accent color
    @Published
    private(set) var accentColor: AccentColor = .blue
    func setAccentColor(_ value: AccentColor) {
        accentColor = value
        userDefaults.set(value.rawValue, forKey: PrefKey.accentColor)
        themeManager.setAccent(value)
    }

    @Published
    private(set) var overlayOpacity: Double = overlayOpacityDefault
    func setOverlayOpacity(_ value: Double) {
        overlayOpacity = Self.clamp(value, to: Self.overlayOpacityRange)
        userDefaults.set(overlayOpacity, forKey: PrefKey.overlayOpacity)
    }

    @Published
    private(set) var overlayShowMinutesBefore: Int = overlayShowMinutesDefault
    func setOverlayShowMinutesBefore(_ value: Int) {
        overlayShowMinutesBefore = Self.clamp(value, to: Self.overlayShowMinutesRange)
        userDefaults.set(overlayShowMinutesBefore, forKey: PrefKey.overlayShowMinutesBefore)
    }

    @Published
    private(set) var fontSize: FontSize = .medium
    func setFontSize(_ value: FontSize) {
        fontSize = value
        userDefaults.set(value.rawValue, forKey: PrefKey.fontSize)
    }

    @Published
    private(set) var minimalMode: Bool = false
    func setMinimalMode(_ value: Bool) {
        minimalMode = value
        userDefaults.set(value, forKey: PrefKey.minimalMode)
    }

    @Published
    private(set) var showOnAllDisplays: Bool = true
    func setShowOnAllDisplays(_ value: Bool) {
        showOnAllDisplays = value
        userDefaults.set(value, forKey: PrefKey.showOnAllDisplays)
    }

    /// Sound
    @Published
    private(set) var playAlertSound: Bool = true
    func setPlayAlertSound(_ value: Bool) {
        playAlertSound = value
        userDefaults.set(value, forKey: PrefKey.playAlertSound)
    }

    /// Convenience aliases for overlay scheduling
    var soundEnabled: Bool {
        playAlertSound
    }

    var soundMinutesBefore: Int {
        defaultAlertMinutes
    }

    @Published
    private(set) var alertVolume: Double = alertVolumeDefault
    func setAlertVolume(_ value: Double) {
        alertVolume = Self.clamp(value, to: Self.alertVolumeRange)
        userDefaults.set(alertVolume, forKey: PrefKey.alertVolume)
    }

    /// Focus mode
    @Published
    private(set) var overrideFocusMode: Bool = true
    func setOverrideFocusMode(_ value: Bool) {
        overrideFocusMode = value
        userDefaults.set(value, forKey: PrefKey.overrideFocusMode)
    }

    /// Smart suppression — suppress overlay when the meeting app is already in the foreground
    @Published
    private(set) var smartSuppression: Bool = true
    func setSmartSuppression(_ value: Bool) {
        smartSuppression = value
        userDefaults.set(value, forKey: PrefKey.smartSuppression)
    }

    /// Auto-join
    @Published
    private(set) var autoJoinEnabled: Bool = false
    func setAutoJoinEnabled(_ value: Bool) {
        autoJoinEnabled = value
        userDefaults.set(value, forKey: PrefKey.autoJoinEnabled)
    }

    /// Snooze
    @Published
    private(set) var allowSnooze: Bool = true
    func setAllowSnooze(_ value: Bool) {
        allowSnooze = value
        userDefaults.set(value, forKey: PrefKey.allowSnooze)
    }

    /// Menu bar display
    @Published
    private(set) var menuBarDisplayMode: MenuBarDisplayMode = .icon
    func setMenuBarDisplayMode(_ value: MenuBarDisplayMode) {
        menuBarDisplayMode = value
        userDefaults.set(value.rawValue, forKey: PrefKey.menuBarDisplayMode)
    }

    @Published
    private(set) var showTodayOnlyInMenuBar: Bool = false
    func setShowTodayOnlyInMenuBar(_ value: Bool) {
        showTodayOnlyInMenuBar = value
        userDefaults.set(value, forKey: PrefKey.showTodayOnlyInMenuBar)
    }

    /// Launch at login — defaults to true so the app survives reboots.
    @Published
    private(set) var launchAtLogin: Bool = true
    func setLaunchAtLogin(_ value: Bool) {
        launchAtLogin = value
        userDefaults.set(value, forKey: PrefKey.launchAtLogin)
        loginItemManager.updateRegistration(enabled: value)
    }

    /// Onboarding — tracks whether the user has completed the first-launch onboarding flow.
    @Published
    private(set) var hasCompletedOnboarding: Bool = false
    func setHasCompletedOnboarding(_ value: Bool) {
        hasCompletedOnboarding = value
        userDefaults.set(value, forKey: PrefKey.hasCompletedOnboarding)
    }

    /// Reconciles the stored preference with the actual system login item state.
    /// Only overrides the preference when the system definitively reports `.enabled`.
    /// In unsigned/dev builds, SMAppService may report `.notRegistered` even when
    /// the user toggled the preference on — we don't override the preference in that case.
    func syncLoginItemWithSystem() {
        let systemEnabled = loginItemManager.isRegisteredWithSystem
        if systemEnabled, !launchAtLogin {
            // System says enabled but preference says off — user enabled via System Settings
            launchAtLogin = true
            userDefaults.set(true, forKey: PrefKey.launchAtLogin)
        }
        // Do NOT flip launchAtLogin to false when system reports not-registered,
        // because in dev/unsigned builds this is always the case.
    }

    init(
        userDefaults: UserDefaults = .standard,
        themeManager: ThemeManager,
        loginItemManager: any LoginItemManaging = LoginItemManager(),
    ) {
        self.userDefaults = userDefaults
        self.themeManager = themeManager
        self.loginItemManager = loginItemManager
        loadPreferences()
    }

    // MARK: - Clamping

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        max(range.lowerBound, min(value, range.upperBound))
    }

    private func loadThemePreferences() {
        if let themeRawValue = userDefaults.object(forKey: PrefKey.themeMode) as? String,
           let theme = ThemeMode(rawValue: themeRawValue)
        {
            themeMode = theme
            themeManager.setTheme(theme)
        } else if let legacyRaw = userDefaults.object(forKey: "appearanceTheme") as? String {
            // Migration from old AppTheme: "dark" -> "darkBlue"
            let migrated: ThemeMode = switch legacyRaw {
            case "light": .light
            case "dark": .darkBlue
            default: .system
            }
            themeMode = migrated
            themeManager.setTheme(migrated)
            userDefaults.set(migrated.rawValue, forKey: PrefKey.themeMode)
        } else {
            themeManager.setTheme(.system)
        }

        if let accentRaw = userDefaults.object(forKey: PrefKey.accentColor) as? String,
           let accent = AccentColor(rawValue: accentRaw)
        {
            accentColor = accent
        }
        themeManager.setAccent(accentColor)
    }

    private func loadPreferences() {
        defaultAlertMinutes = Self.clamp(
            userDefaults.object(forKey: PrefKey.defaultAlertMinutes) as? Int ?? Self.defaultAlertMinutesDefault,
            to: Self.alertMinutesRange,
        )
        useLengthBasedTiming = userDefaults.bool(forKey: PrefKey.useLengthBasedTiming)
        shortMeetingAlertMinutes = Self.clamp(
            userDefaults.object(forKey: PrefKey.shortMeetingAlertMinutes) as? Int ?? Self.shortMeetingAlertDefault,
            to: Self.alertMinutesRange,
        )
        mediumMeetingAlertMinutes = Self.clamp(
            userDefaults.object(forKey: PrefKey.mediumMeetingAlertMinutes) as? Int ?? Self.mediumMeetingAlertDefault,
            to: Self.alertMinutesRange,
        )
        longMeetingAlertMinutes = Self.clamp(
            userDefaults.object(forKey: PrefKey.longMeetingAlertMinutes) as? Int ?? Self.longMeetingAlertDefault,
            to: Self.alertMinutesRange,
        )

        syncIntervalSeconds = Self.clamp(
            userDefaults.object(forKey: PrefKey.syncIntervalSeconds) as? Int ?? Self.syncIntervalDefault,
            to: Self.syncIntervalRange,
        )
        includeAllDayEvents = userDefaults.bool(forKey: PrefKey.includeAllDayEvents)

        loadThemePreferences()

        overlayOpacity = Self.clamp(
            userDefaults.object(forKey: PrefKey.overlayOpacity) as? Double ?? Self.overlayOpacityDefault,
            to: Self.overlayOpacityRange,
        )
        overlayShowMinutesBefore = Self.clamp(
            userDefaults.object(forKey: PrefKey.overlayShowMinutesBefore) as? Int ?? Self.overlayShowMinutesDefault,
            to: Self.overlayShowMinutesRange,
        )

        if let fontSizeRawValue = userDefaults.object(forKey: PrefKey.fontSize) as? String,
           let fontSize = FontSize(rawValue: fontSizeRawValue)
        {
            self.fontSize = fontSize
        }

        minimalMode = userDefaults.bool(forKey: PrefKey.minimalMode)
        showOnAllDisplays = userDefaults.object(forKey: PrefKey.showOnAllDisplays) as? Bool ?? true

        playAlertSound = userDefaults.object(forKey: PrefKey.playAlertSound) as? Bool ?? true
        alertVolume = Self.clamp(
            userDefaults.object(forKey: PrefKey.alertVolume) as? Double ?? Self.alertVolumeDefault,
            to: Self.alertVolumeRange,
        )

        overrideFocusMode = userDefaults.object(forKey: PrefKey.overrideFocusMode) as? Bool ?? true
        smartSuppression = userDefaults.object(forKey: PrefKey.smartSuppression) as? Bool ?? true
        autoJoinEnabled = userDefaults.bool(forKey: PrefKey.autoJoinEnabled)
        allowSnooze = userDefaults.object(forKey: PrefKey.allowSnooze) as? Bool ?? true

        if let modeRawValue = userDefaults.object(forKey: PrefKey.menuBarDisplayMode) as? String,
           let mode = MenuBarDisplayMode(rawValue: modeRawValue)
        {
            menuBarDisplayMode = mode
        }

        showTodayOnlyInMenuBar = userDefaults.bool(forKey: PrefKey.showTodayOnlyInMenuBar)

        if userDefaults.object(forKey: PrefKey.launchAtLogin) == nil {
            // First launch — register as login item by default
            launchAtLogin = true
            userDefaults.set(true, forKey: PrefKey.launchAtLogin)
            loginItemManager.updateRegistration(enabled: true)
        } else {
            launchAtLogin = userDefaults.object(forKey: PrefKey.launchAtLogin) as? Bool ?? true
        }

        hasCompletedOnboarding = userDefaults.bool(forKey: PrefKey.hasCompletedOnboarding)
    }

    // MARK: - Alert Timing Resolution

    /// Returns the alert timing in minutes for a given event.
    ///
    /// Resolution order:
    /// 1. Per-event override (if non-nil) — returned as-is, including `0` ("no alert").
    /// 2. Length-based timing rules (if enabled in preferences).
    /// 3. Global default alert minutes.
    func alertMinutes(for event: Event, override: Int? = nil) -> Int {
        if let override {
            return override
        }

        guard useLengthBasedTiming else {
            return defaultAlertMinutes
        }

        let durationMinutes = Int(event.duration / Double(Self.secondsPerMinute))

        if durationMinutes < Self.shortMeetingThresholdMinutes { return shortMeetingAlertMinutes }
        if durationMinutes <= Self.longMeetingThresholdMinutes { return mediumMeetingAlertMinutes }
        return longMeetingAlertMinutes
    }
}
