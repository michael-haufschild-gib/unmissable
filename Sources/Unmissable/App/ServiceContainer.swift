import Foundation

/// Owns the construction and lifecycle of all application services.
/// AppState reads from this container instead of constructing services directly.
@MainActor
final class ServiceContainer {
    let databaseManager: DatabaseManager
    let preferencesManager: PreferencesManager
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
        databaseManager: DatabaseManager = .shared,
        preferencesManager: PreferencesManager = PreferencesManager()
    ) {
        self.databaseManager = databaseManager
        self.preferencesManager = preferencesManager

        focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        calendarService = CalendarService(
            preferencesManager: preferencesManager, databaseManager: databaseManager
        )
        overlayManager = OverlayManager(
            preferencesManager: preferencesManager, focusModeManager: focusModeManager
        )
        eventScheduler = EventScheduler(preferencesManager: preferencesManager)
        menuBarPreviewManager = MenuBarPreviewManager(preferencesManager: preferencesManager)
        shortcutsManager = ShortcutsManager()
        healthMonitor = HealthMonitor()
        meetingDetailsPopupManager = MeetingDetailsPopupManager()
        updateManager = UpdateManager()

        // Wire cross-service dependencies
        overlayManager.setEventScheduler(eventScheduler)
        shortcutsManager.setup(overlayManager: overlayManager)
        healthMonitor.setup(
            calendarService: calendarService,
            overlayManager: overlayManager
        )
    }
}
