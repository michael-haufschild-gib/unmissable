import Combine
import Foundation

// Import our custom theme system
import SwiftUI

@MainActor
final class PreferencesManager: ObservableObject {
    private let userDefaults = UserDefaults.standard

    /// Alert timing (validated to 0-60 minutes)
    @Published var defaultAlertMinutes: Int = 1 {
        didSet {
            let validated = max(0, min(defaultAlertMinutes, 60))
            if validated != defaultAlertMinutes { defaultAlertMinutes = validated
                return
            }
            userDefaults.set(validated, forKey: "defaultAlertMinutes")
        }
    }

    @Published var useLengthBasedTiming: Bool = false {
        didSet { userDefaults.set(useLengthBasedTiming, forKey: "useLengthBasedTiming") }
    }

    @Published var shortMeetingAlertMinutes: Int = 1 {
        didSet {
            let validated = max(0, min(shortMeetingAlertMinutes, 60))
            if validated != shortMeetingAlertMinutes { shortMeetingAlertMinutes = validated
                return
            }
            userDefaults.set(validated, forKey: "shortMeetingAlertMinutes")
        }
    }

    @Published var mediumMeetingAlertMinutes: Int = 2 {
        didSet {
            let validated = max(0, min(mediumMeetingAlertMinutes, 60))
            if validated != mediumMeetingAlertMinutes { mediumMeetingAlertMinutes = validated
                return
            }
            userDefaults.set(validated, forKey: "mediumMeetingAlertMinutes")
        }
    }

    @Published var longMeetingAlertMinutes: Int = 5 {
        didSet {
            let validated = max(0, min(longMeetingAlertMinutes, 60))
            if validated != longMeetingAlertMinutes { longMeetingAlertMinutes = validated
                return
            }
            userDefaults.set(validated, forKey: "longMeetingAlertMinutes")
        }
    }

    /// Sync settings (validated to 30-3600 seconds)
    @Published var syncIntervalSeconds: Int = 60 {
        didSet {
            let validated = max(30, min(syncIntervalSeconds, 3600))
            if validated != syncIntervalSeconds { syncIntervalSeconds = validated
                return
            }
            userDefaults.set(validated, forKey: "syncIntervalSeconds")
        }
    }

    @Published var includeAllDayEvents: Bool = false {
        didSet { userDefaults.set(includeAllDayEvents, forKey: "includeAllDayEvents") }
    }

    /// Appearance - Updated to use new custom theme system
    @Published var appearanceTheme: AppTheme = .system {
        didSet {
            userDefaults.set(appearanceTheme.rawValue, forKey: "appearanceTheme")
            // Update the global theme manager
            ThemeManager.shared.setTheme(appearanceTheme)
        }
    }

    @Published var overlayOpacity: Double = 0.9 {
        didSet {
            let validated = max(0.1, min(overlayOpacity, 1.0))
            if validated != overlayOpacity { overlayOpacity = validated
                return
            }
            userDefaults.set(validated, forKey: "overlayOpacity")
        }
    }

    @Published var overlayShowMinutesBefore: Int = 5 {
        didSet {
            let validated = max(1, min(overlayShowMinutesBefore, 60))
            if validated != overlayShowMinutesBefore { overlayShowMinutesBefore = validated
                return
            }
            userDefaults.set(validated, forKey: "overlayShowMinutesBefore")
        }
    }

    @Published var fontSize: FontSize = .medium {
        didSet { userDefaults.set(fontSize.rawValue, forKey: "fontSize") }
    }

    @Published var minimalMode: Bool = false {
        didSet { userDefaults.set(minimalMode, forKey: "minimalMode") }
    }

    @Published var showOnAllDisplays: Bool = true {
        didSet { userDefaults.set(showOnAllDisplays, forKey: "showOnAllDisplays") }
    }

    /// Sound
    @Published var playAlertSound: Bool = true {
        didSet { userDefaults.set(playAlertSound, forKey: "playAlertSound") }
    }

    /// Convenience aliases for overlay scheduling
    var soundEnabled: Bool {
        playAlertSound
    }

    var soundMinutesBefore: Int {
        defaultAlertMinutes
    }

    @Published var alertVolume: Double = 0.7 {
        didSet {
            let validated = max(0.0, min(alertVolume, 1.0))
            if validated != alertVolume { alertVolume = validated
                return
            }
            userDefaults.set(validated, forKey: "alertVolume")
        }
    }

    /// Focus mode
    @Published var overrideFocusMode: Bool = true {
        didSet { userDefaults.set(overrideFocusMode, forKey: "overrideFocusMode") }
    }

    /// Auto-join
    @Published var autoJoinEnabled: Bool = false {
        didSet { userDefaults.set(autoJoinEnabled, forKey: "autoJoinEnabled") }
    }

    /// Snooze
    @Published var allowSnooze: Bool = true {
        didSet { userDefaults.set(allowSnooze, forKey: "allowSnooze") }
    }

    /// Menu bar display
    @Published var menuBarDisplayMode: MenuBarDisplayMode = .icon {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode")
        }
    }

    @Published var showTodayOnlyInMenuBar: Bool = false {
        didSet { userDefaults.set(showTodayOnlyInMenuBar, forKey: "showTodayOnlyInMenuBar") }
    }

    init() {
        loadPreferences()
    }

    private func loadPreferences() {
        defaultAlertMinutes = userDefaults.object(forKey: "defaultAlertMinutes") as? Int ?? 1
        useLengthBasedTiming = userDefaults.bool(forKey: "useLengthBasedTiming")
        shortMeetingAlertMinutes = userDefaults.object(forKey: "shortMeetingAlertMinutes") as? Int ?? 1
        mediumMeetingAlertMinutes =
            userDefaults.object(forKey: "mediumMeetingAlertMinutes") as? Int ?? 2
        longMeetingAlertMinutes = userDefaults.object(forKey: "longMeetingAlertMinutes") as? Int ?? 5

        syncIntervalSeconds = userDefaults.object(forKey: "syncIntervalSeconds") as? Int ?? 60
        includeAllDayEvents = userDefaults.bool(forKey: "includeAllDayEvents")

        if let themeRawValue = userDefaults.object(forKey: "appearanceTheme") as? String,
           let theme = AppTheme(rawValue: themeRawValue)
        {
            appearanceTheme = theme
            ThemeManager.shared.setTheme(theme)
        } else {
            ThemeManager.shared.setTheme(.system)
        }

        overlayOpacity = userDefaults.object(forKey: "overlayOpacity") as? Double ?? 0.9
        overlayShowMinutesBefore = userDefaults.object(forKey: "overlayShowMinutesBefore") as? Int ?? 5

        if let fontSizeRawValue = userDefaults.object(forKey: "fontSize") as? String,
           let fontSize = FontSize(rawValue: fontSizeRawValue)
        {
            self.fontSize = fontSize
        }

        minimalMode = userDefaults.bool(forKey: "minimalMode")
        showOnAllDisplays = userDefaults.object(forKey: "showOnAllDisplays") as? Bool ?? true

        playAlertSound = userDefaults.object(forKey: "playAlertSound") as? Bool ?? true
        alertVolume = userDefaults.object(forKey: "alertVolume") as? Double ?? 0.7

        overrideFocusMode = userDefaults.object(forKey: "overrideFocusMode") as? Bool ?? true
        autoJoinEnabled = userDefaults.bool(forKey: "autoJoinEnabled")
        allowSnooze = userDefaults.object(forKey: "allowSnooze") as? Bool ?? true

        if let modeRawValue = userDefaults.object(forKey: "menuBarDisplayMode") as? String,
           let mode = MenuBarDisplayMode(rawValue: modeRawValue)
        {
            menuBarDisplayMode = mode
        }

        showTodayOnlyInMenuBar = userDefaults.bool(forKey: "showTodayOnlyInMenuBar")
    }

    func alertMinutes(for event: Event) -> Int {
        guard useLengthBasedTiming else {
            return defaultAlertMinutes
        }

        let durationMinutes = Int(event.duration / 60)

        if durationMinutes < 30 {
            return shortMeetingAlertMinutes
        } else if durationMinutes <= 60 {
            return mediumMeetingAlertMinutes
        } else {
            return longMeetingAlertMinutes
        }
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
