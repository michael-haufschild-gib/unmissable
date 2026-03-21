import Combine
import Foundation

// MARK: - Type-safe UserDefaults Keys

private enum PrefKey: String {
    case defaultAlertMinutes
    case useLengthBasedTiming
    case shortMeetingAlertMinutes
    case mediumMeetingAlertMinutes
    case longMeetingAlertMinutes
    case syncIntervalSeconds
    case includeAllDayEvents
    case appearanceTheme
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
    private let userDefaults = UserDefaults.standard

    /// Alert timing (validated to 0-60 minutes)
    @Published
    var defaultAlertMinutes: Int = 1 {
        didSet {
            let v = clamped(defaultAlertMinutes, key: .defaultAlertMinutes, range: 0 ... 60)
            if v != defaultAlertMinutes { defaultAlertMinutes = v }
        }
    }

    @Published
    var useLengthBasedTiming: Bool = false {
        didSet { userDefaults.set(useLengthBasedTiming, forKey: PrefKey.useLengthBasedTiming) }
    }

    @Published
    var shortMeetingAlertMinutes: Int = 1 {
        didSet {
            let v = clamped(shortMeetingAlertMinutes, key: .shortMeetingAlertMinutes, range: 0 ... 60)
            if v != shortMeetingAlertMinutes { shortMeetingAlertMinutes = v }
        }
    }

    @Published
    var mediumMeetingAlertMinutes: Int = 2 {
        didSet {
            let v = clamped(mediumMeetingAlertMinutes, key: .mediumMeetingAlertMinutes, range: 0 ... 60)
            if v != mediumMeetingAlertMinutes { mediumMeetingAlertMinutes = v }
        }
    }

    @Published
    var longMeetingAlertMinutes: Int = 5 {
        didSet {
            let v = clamped(longMeetingAlertMinutes, key: .longMeetingAlertMinutes, range: 0 ... 60)
            if v != longMeetingAlertMinutes { longMeetingAlertMinutes = v }
        }
    }

    /// Sync settings (validated to 30-3600 seconds)
    @Published
    var syncIntervalSeconds: Int = 60 {
        didSet {
            let v = clamped(syncIntervalSeconds, key: .syncIntervalSeconds, range: 30 ... 3600)
            if v != syncIntervalSeconds { syncIntervalSeconds = v }
        }
    }

    @Published
    var includeAllDayEvents: Bool = false {
        didSet { userDefaults.set(includeAllDayEvents, forKey: PrefKey.includeAllDayEvents) }
    }

    /// Appearance - Updated to use new custom theme system
    @Published
    var appearanceTheme: AppTheme = .system {
        didSet {
            userDefaults.set(appearanceTheme.rawValue, forKey: PrefKey.appearanceTheme)
            ThemeManager.shared.setTheme(appearanceTheme)
        }
    }

    @Published
    var overlayOpacity: Double = 0.9 {
        didSet {
            let v = clamped(overlayOpacity, key: .overlayOpacity, range: 0.1 ... 1.0)
            if v != overlayOpacity { overlayOpacity = v }
        }
    }

    @Published
    var overlayShowMinutesBefore: Int = 5 {
        didSet {
            let v = clamped(overlayShowMinutesBefore, key: .overlayShowMinutesBefore, range: 1 ... 60)
            if v != overlayShowMinutesBefore { overlayShowMinutesBefore = v }
        }
    }

    @Published
    var fontSize: FontSize = .medium {
        didSet { userDefaults.set(fontSize.rawValue, forKey: PrefKey.fontSize) }
    }

    @Published
    var minimalMode: Bool = false {
        didSet { userDefaults.set(minimalMode, forKey: PrefKey.minimalMode) }
    }

    @Published
    var showOnAllDisplays: Bool = true {
        didSet { userDefaults.set(showOnAllDisplays, forKey: PrefKey.showOnAllDisplays) }
    }

    /// Sound
    @Published
    var playAlertSound: Bool = true {
        didSet { userDefaults.set(playAlertSound, forKey: PrefKey.playAlertSound) }
    }

    /// Convenience aliases for overlay scheduling
    var soundEnabled: Bool {
        playAlertSound
    }

    var soundMinutesBefore: Int {
        defaultAlertMinutes
    }

    @Published
    var alertVolume: Double = 0.7 {
        didSet {
            let v = clamped(alertVolume, key: .alertVolume, range: 0.0 ... 1.0)
            if v != alertVolume { alertVolume = v }
        }
    }

    /// Focus mode
    @Published
    var overrideFocusMode: Bool = true {
        didSet { userDefaults.set(overrideFocusMode, forKey: PrefKey.overrideFocusMode) }
    }

    /// Auto-join
    @Published
    var autoJoinEnabled: Bool = false {
        didSet { userDefaults.set(autoJoinEnabled, forKey: PrefKey.autoJoinEnabled) }
    }

    /// Snooze
    @Published
    var allowSnooze: Bool = true {
        didSet { userDefaults.set(allowSnooze, forKey: PrefKey.allowSnooze) }
    }

    /// Menu bar display
    @Published
    var menuBarDisplayMode: MenuBarDisplayMode = .icon {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: PrefKey.menuBarDisplayMode)
        }
    }

    @Published
    var showTodayOnlyInMenuBar: Bool = false {
        didSet { userDefaults.set(showTodayOnlyInMenuBar, forKey: PrefKey.showTodayOnlyInMenuBar) }
    }

    init() {
        loadPreferences()
    }

    // MARK: - Clamped Persistence

    /// Returns clamped value and persists to UserDefaults.
    /// Caller must check return value against current property and re-assign if different.
    private func clamped(_ value: Int, key: PrefKey, range: ClosedRange<Int>) -> Int {
        let result = max(range.lowerBound, min(value, range.upperBound))
        userDefaults.set(result, forKey: key)
        return result
    }

    private func clamped(_ value: Double, key: PrefKey, range: ClosedRange<Double>) -> Double {
        let result = max(range.lowerBound, min(value, range.upperBound))
        userDefaults.set(result, forKey: key)
        return result
    }

    private func loadPreferences() {
        defaultAlertMinutes = userDefaults.object(forKey: PrefKey.defaultAlertMinutes) as? Int ?? 1
        useLengthBasedTiming = userDefaults.bool(forKey: PrefKey.useLengthBasedTiming)
        shortMeetingAlertMinutes = userDefaults.object(forKey: PrefKey.shortMeetingAlertMinutes) as? Int ?? 1
        mediumMeetingAlertMinutes =
            userDefaults.object(forKey: PrefKey.mediumMeetingAlertMinutes) as? Int ?? 2
        longMeetingAlertMinutes = userDefaults.object(forKey: PrefKey.longMeetingAlertMinutes) as? Int ?? 5

        syncIntervalSeconds = userDefaults.object(forKey: PrefKey.syncIntervalSeconds) as? Int ?? 60
        includeAllDayEvents = userDefaults.bool(forKey: PrefKey.includeAllDayEvents)

        if let themeRawValue = userDefaults.object(forKey: PrefKey.appearanceTheme) as? String,
           let theme = AppTheme(rawValue: themeRawValue)
        {
            appearanceTheme = theme
            ThemeManager.shared.setTheme(theme)
        } else {
            ThemeManager.shared.setTheme(.system)
        }

        overlayOpacity = userDefaults.object(forKey: PrefKey.overlayOpacity) as? Double ?? 0.9
        overlayShowMinutesBefore = userDefaults.object(forKey: PrefKey.overlayShowMinutesBefore) as? Int ?? 5

        if let fontSizeRawValue = userDefaults.object(forKey: PrefKey.fontSize) as? String,
           let fontSize = FontSize(rawValue: fontSizeRawValue)
        {
            self.fontSize = fontSize
        }

        minimalMode = userDefaults.bool(forKey: PrefKey.minimalMode)
        showOnAllDisplays = userDefaults.object(forKey: PrefKey.showOnAllDisplays) as? Bool ?? true

        playAlertSound = userDefaults.object(forKey: PrefKey.playAlertSound) as? Bool ?? true
        alertVolume = userDefaults.object(forKey: PrefKey.alertVolume) as? Double ?? 0.7

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

    func alertMinutes(for event: Event) -> Int {
        guard useLengthBasedTiming else {
            return defaultAlertMinutes
        }

        let durationMinutes = Int(event.duration / 60)

        if durationMinutes < 30 { return shortMeetingAlertMinutes }
        if durationMinutes <= 60 { return mediumMeetingAlertMinutes }
        return longMeetingAlertMinutes
    }
}

// Note: AppTheme is now defined in ThemeManager.swift

enum FontSize: String, CaseIterable {
    case small
    case medium
    case large

    var scale: Double {
        switch self {
        case .small:
            0.8
        case .medium:
            1.0
        case .large:
            1.4
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
