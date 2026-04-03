import Foundation

/// Owns the construction and lifecycle of all application services.
/// AppState reads from this container instead of constructing services directly.
@MainActor
final class ServiceContainer {
    let databaseManager: any DatabaseManaging
    let linkParser: LinkParser
    let themeManager: ThemeManager
    let preferencesManager: PreferencesManager
    let soundManager: SoundManager
    let focusModeManager: FocusModeManager
    let calendarService: CalendarService
    let overlayManager: OverlayManager
    let eventScheduler: EventScheduler
    let shortcutsManager: ShortcutsManager
    let healthMonitor: HealthMonitor
    let menuBarPreviewManager: MenuBarPreviewManager
    let meetingDetailsPopupManager: MeetingDetailsPopupManager
    let updateManager: UpdateManager

    init(
        databaseManager: any DatabaseManaging,
        linkParser: LinkParser = LinkParser(),
        themeManager: ThemeManager = ThemeManager(),
    ) {
        self.databaseManager = databaseManager
        self.linkParser = linkParser
        self.themeManager = themeManager

        preferencesManager = PreferencesManager(themeManager: themeManager)
        soundManager = SoundManager(preferencesManager: preferencesManager)
        focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        calendarService = CalendarService(
            preferencesManager: preferencesManager,
            databaseManager: databaseManager,
            linkParser: linkParser,
        )
        eventScheduler = EventScheduler(
            preferencesManager: preferencesManager, linkParser: linkParser,
        )
        overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            eventScheduler: eventScheduler,
            soundManager: soundManager,
            focusModeManager: focusModeManager,
            linkParser: linkParser,
            themeManager: themeManager,
        )
        menuBarPreviewManager = MenuBarPreviewManager(preferencesManager: preferencesManager)
        shortcutsManager = ShortcutsManager(
            overlayManager: overlayManager, linkParser: linkParser,
        )
        healthMonitor = HealthMonitor(
            calendarService: calendarService,
            overlayManager: overlayManager,
        )
        meetingDetailsPopupManager = MeetingDetailsPopupManager(themeManager: themeManager)
        updateManager = UpdateManager()
    }
}
