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
    private static let overlayShowMinutesRange = 1 ... 60
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

    init(userDefaults: UserDefaults = .standard, themeManager: ThemeManager) {
        self.userDefaults = userDefaults
        self.themeManager = themeManager
        loadPreferences()
    }

    // MARK: - Clamping

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        max(range.lowerBound, min(value, range.upperBound))
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
            themeManager.setAccent(accent)
        }

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
        autoJoinEnabled = userDefaults.bool(forKey: PrefKey.autoJoinEnabled)
        allowSnooze = userDefaults.object(forKey: PrefKey.allowSnooze) as? Bool ?? true

        if let modeRawValue = userDefaults.object(forKey: PrefKey.menuBarDisplayMode) as? String,
           let mode = MenuBarDisplayMode(rawValue: modeRawValue)
        {
            menuBarDisplayMode = mode
        }

        showTodayOnlyInMenuBar = userDefaults.bool(forKey: PrefKey.showTodayOnlyInMenuBar)
    }

    // MARK: - Bindings for SwiftUI

    /// Bindings that route through setter methods, for use in SwiftUI Pickers/Toggles/Sliders.
    var defaultAlertMinutesBinding: Binding<Int> {
        Binding(
            get: { self.defaultAlertMinutes },
            set: { self.setDefaultAlertMinutes($0) },
        )
    }

    var useLengthBasedTimingBinding: Binding<Bool> {
        Binding(
            get: { self.useLengthBasedTiming },
            set: { self.setUseLengthBasedTiming($0) },
        )
    }

    var shortMeetingAlertMinutesBinding: Binding<Int> {
        Binding(
            get: { self.shortMeetingAlertMinutes },
            set: { self.setShortMeetingAlertMinutes($0) },
        )
    }

    var mediumMeetingAlertMinutesBinding: Binding<Int> {
        Binding(
            get: { self.mediumMeetingAlertMinutes },
            set: { self.setMediumMeetingAlertMinutes($0) },
        )
    }

    var longMeetingAlertMinutesBinding: Binding<Int> {
        Binding(
            get: { self.longMeetingAlertMinutes },
            set: { self.setLongMeetingAlertMinutes($0) },
        )
    }

    var syncIntervalSecondsBinding: Binding<Int> {
        Binding(
            get: { self.syncIntervalSeconds },
            set: { self.setSyncIntervalSeconds($0) },
        )
    }

    var includeAllDayEventsBinding: Binding<Bool> {
        Binding(
            get: { self.includeAllDayEvents },
            set: { self.setIncludeAllDayEvents($0) },
        )
    }

    var themeModeBinding: Binding<ThemeMode> {
        Binding(
            get: { self.themeMode },
            set: { self.setThemeMode($0) },
        )
    }

    var accentColorBinding: Binding<AccentColor> {
        Binding(
            get: { self.accentColor },
            set: { self.setAccentColor($0) },
        )
    }

    var overlayOpacityBinding: Binding<Double> {
        Binding(
            get: { self.overlayOpacity },
            set: { self.setOverlayOpacity($0) },
        )
    }

    var overlayShowMinutesBeforeBinding: Binding<Int> {
        Binding(
            get: { self.overlayShowMinutesBefore },
            set: { self.setOverlayShowMinutesBefore($0) },
        )
    }

    var menuBarDisplayModeBinding: Binding<MenuBarDisplayMode> {
        Binding(
            get: { self.menuBarDisplayMode },
            set: { self.setMenuBarDisplayMode($0) },
        )
    }

    var showTodayOnlyInMenuBarBinding: Binding<Bool> {
        Binding(
            get: { self.showTodayOnlyInMenuBar },
            set: { self.setShowTodayOnlyInMenuBar($0) },
        )
    }

    var alertVolumeBinding: Binding<Double> {
        Binding(
            get: { self.alertVolume },
            set: { self.setAlertVolume($0) },
        )
    }

    func alertMinutes(for event: Event) -> Int {
        guard useLengthBasedTiming else {
            return defaultAlertMinutes
        }

        let durationMinutes = Int(event.duration / Double(Self.secondsPerMinute))

        if durationMinutes < Self.shortMeetingThresholdMinutes { return shortMeetingAlertMinutes }
        if durationMinutes <= Self.longMeetingThresholdMinutes { return mediumMeetingAlertMinutes }
        return longMeetingAlertMinutes
    }
}

enum FontSize: String, CaseIterable {
    case small
    case medium
    case large

    private static let smallScale: Double = 0.8
    private static let mediumScale: Double = 1.0
    private static let largeScale: Double = 1.4

    var scale: Double {
        switch self {
        case .small:
            Self.smallScale

        case .medium:
            Self.mediumScale

        case .large:
            Self.largeScale
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable {
    case icon
    case timer
    case nameTimer

    var displayName: String {
        switch self {
        case .icon:
            "Icon Only"

        case .timer:
            "Timer"

        case .nameTimer:
            "Name + Timer"
        }
    }
}
