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

    // MARK: - Clamped Properties

    // These use a private @Published backing store with a computed public property
    // so that values are clamped before assignment, producing exactly one notification.
    // Combine subscribers use the $_name projection; SwiftUI Bindings use the computed property.

    /// Alert timing (validated to 0-60 minutes)
    @Published
    private(set) var defaultAlertMinutes: Int = 1
    func setDefaultAlertMinutes(_ value: Int) {
        defaultAlertMinutes = Self.clamp(value, to: 0 ... 60)
        userDefaults.set(defaultAlertMinutes, forKey: PrefKey.defaultAlertMinutes)
    }

    @Published
    var useLengthBasedTiming: Bool = false {
        didSet { userDefaults.set(useLengthBasedTiming, forKey: PrefKey.useLengthBasedTiming) }
    }

    @Published
    private(set) var shortMeetingAlertMinutes: Int = 1
    func setShortMeetingAlertMinutes(_ value: Int) {
        shortMeetingAlertMinutes = Self.clamp(value, to: 0 ... 60)
        userDefaults.set(shortMeetingAlertMinutes, forKey: PrefKey.shortMeetingAlertMinutes)
    }

    @Published
    private(set) var mediumMeetingAlertMinutes: Int = 2
    func setMediumMeetingAlertMinutes(_ value: Int) {
        mediumMeetingAlertMinutes = Self.clamp(value, to: 0 ... 60)
        userDefaults.set(mediumMeetingAlertMinutes, forKey: PrefKey.mediumMeetingAlertMinutes)
    }

    @Published
    private(set) var longMeetingAlertMinutes: Int = 5
    func setLongMeetingAlertMinutes(_ value: Int) {
        longMeetingAlertMinutes = Self.clamp(value, to: 0 ... 60)
        userDefaults.set(longMeetingAlertMinutes, forKey: PrefKey.longMeetingAlertMinutes)
    }

    /// Sync settings (validated to 30-3600 seconds)
    @Published
    private(set) var syncIntervalSeconds: Int = 60
    func setSyncIntervalSeconds(_ value: Int) {
        syncIntervalSeconds = Self.clamp(value, to: 30 ... 3600)
        userDefaults.set(syncIntervalSeconds, forKey: PrefKey.syncIntervalSeconds)
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
    private(set) var overlayOpacity: Double = 0.9
    func setOverlayOpacity(_ value: Double) {
        overlayOpacity = Self.clamp(value, to: 0.1 ... 1.0)
        userDefaults.set(overlayOpacity, forKey: PrefKey.overlayOpacity)
    }

    @Published
    private(set) var overlayShowMinutesBefore: Int = 5
    func setOverlayShowMinutesBefore(_ value: Int) {
        overlayShowMinutesBefore = Self.clamp(value, to: 1 ... 60)
        userDefaults.set(overlayShowMinutesBefore, forKey: PrefKey.overlayShowMinutesBefore)
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
    private(set) var alertVolume: Double = 0.7
    func setAlertVolume(_ value: Double) {
        alertVolume = Self.clamp(value, to: 0.0 ... 1.0)
        userDefaults.set(alertVolume, forKey: PrefKey.alertVolume)
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

    // MARK: - Clamping

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        max(range.lowerBound, min(value, range.upperBound))
    }

    private func loadPreferences() {
        defaultAlertMinutes = Self.clamp(
            userDefaults.object(forKey: PrefKey.defaultAlertMinutes) as? Int ?? 1, to: 0 ... 60
        )
        useLengthBasedTiming = userDefaults.bool(forKey: PrefKey.useLengthBasedTiming)
        shortMeetingAlertMinutes = Self.clamp(
            userDefaults.object(forKey: PrefKey.shortMeetingAlertMinutes) as? Int ?? 1, to: 0 ... 60
        )
        mediumMeetingAlertMinutes = Self.clamp(
            userDefaults.object(forKey: PrefKey.mediumMeetingAlertMinutes) as? Int ?? 2, to: 0 ... 60
        )
        longMeetingAlertMinutes = Self.clamp(
            userDefaults.object(forKey: PrefKey.longMeetingAlertMinutes) as? Int ?? 5, to: 0 ... 60
        )

        syncIntervalSeconds = Self.clamp(
            userDefaults.object(forKey: PrefKey.syncIntervalSeconds) as? Int ?? 60, to: 30 ... 3600
        )
        includeAllDayEvents = userDefaults.bool(forKey: PrefKey.includeAllDayEvents)

        if let themeRawValue = userDefaults.object(forKey: PrefKey.appearanceTheme) as? String,
           let theme = AppTheme(rawValue: themeRawValue)
        {
            appearanceTheme = theme
            ThemeManager.shared.setTheme(theme)
        } else {
            ThemeManager.shared.setTheme(.system)
        }

        overlayOpacity = Self.clamp(
            userDefaults.object(forKey: PrefKey.overlayOpacity) as? Double ?? 0.9, to: 0.1 ... 1.0
        )
        overlayShowMinutesBefore = Self.clamp(
            userDefaults.object(forKey: PrefKey.overlayShowMinutesBefore) as? Int ?? 5, to: 1 ... 60
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
            userDefaults.object(forKey: PrefKey.alertVolume) as? Double ?? 0.7, to: 0.0 ... 1.0
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

    // MARK: - Clamped Bindings for SwiftUI

    /// Bindings that clamp values on write, for use in SwiftUI Pickers/Sliders.
    var defaultAlertMinutesBinding: Binding<Int> {
        Binding(
            get: { self.defaultAlertMinutes },
            set: { self.setDefaultAlertMinutes($0) }
        )
    }

    var shortMeetingAlertMinutesBinding: Binding<Int> {
        Binding(
            get: { self.shortMeetingAlertMinutes },
            set: { self.setShortMeetingAlertMinutes($0) }
        )
    }

    var mediumMeetingAlertMinutesBinding: Binding<Int> {
        Binding(
            get: { self.mediumMeetingAlertMinutes },
            set: { self.setMediumMeetingAlertMinutes($0) }
        )
    }

    var longMeetingAlertMinutesBinding: Binding<Int> {
        Binding(
            get: { self.longMeetingAlertMinutes },
            set: { self.setLongMeetingAlertMinutes($0) }
        )
    }

    var syncIntervalSecondsBinding: Binding<Int> {
        Binding(
            get: { self.syncIntervalSeconds },
            set: { self.setSyncIntervalSeconds($0) }
        )
    }

    var overlayOpacityBinding: Binding<Double> {
        Binding(
            get: { self.overlayOpacity },
            set: { self.setOverlayOpacity($0) }
        )
    }

    var overlayShowMinutesBeforeBinding: Binding<Int> {
        Binding(
            get: { self.overlayShowMinutesBefore },
            set: { self.setOverlayShowMinutesBefore($0) }
        )
    }

    var alertVolumeBinding: Binding<Double> {
        Binding(
            get: { self.alertVolume },
            set: { self.setAlertVolume($0) }
        )
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
