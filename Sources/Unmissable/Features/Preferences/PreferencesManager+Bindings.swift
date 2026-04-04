import SwiftUI

// MARK: - SwiftUI Bindings

extension PreferencesManager {
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

    var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { self.launchAtLogin },
            set: { self.setLaunchAtLogin($0) },
        )
    }

    var smartSuppressionBinding: Binding<Bool> {
        Binding(
            get: { self.smartSuppression },
            set: { self.setSmartSuppression($0) },
        )
    }
}
