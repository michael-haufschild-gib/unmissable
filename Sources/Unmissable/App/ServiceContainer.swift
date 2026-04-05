import Foundation
import OSLog

/// Owns the construction and lifecycle of all application services.
/// AppState reads from this container instead of constructing services directly.
final class ServiceContainer {
    private let logger = Logger(category: "ServiceContainer")
    let databaseManager: any DatabaseManaging
    let linkParser: LinkParser
    let themeManager: ThemeManager
    let preferencesManager: PreferencesManager
    let soundManager: SoundManager
    let focusModeManager: FocusModeManager
    let calendarService: CalendarService
    let overlayManager: any OverlayManaging
    let eventScheduler: EventScheduler
    let shortcutsManager: ShortcutsManager
    let healthMonitor: HealthMonitor
    let notificationManager: NotificationManager
    let menuBarPreviewManager: MenuBarPreviewManager
    let meetingDetailsPopupManager: any MeetingDetailsPopupManaging
    let activationPolicyManager: ActivationPolicyManager

    init(
        databaseManager: any DatabaseManaging,
        linkParser: LinkParser = LinkParser(),
        themeManager: ThemeManager = ThemeManager(),
        overlayManagerOverride: (any OverlayManaging)? = nil,
        preferencesManagerOverride: PreferencesManager? = nil,
        meetingDetailsPopupManagerOverride: (any MeetingDetailsPopupManaging)? = nil,
    ) {
        self.databaseManager = databaseManager
        self.linkParser = linkParser
        self.themeManager = themeManager

        preferencesManager = preferencesManagerOverride ?? PreferencesManager(themeManager: themeManager)
        soundManager = SoundManager(preferencesManager: preferencesManager)
        focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        calendarService = CalendarService(
            preferencesManager: preferencesManager,
            databaseManager: databaseManager,
            linkParser: linkParser,
        )
        notificationManager = NotificationManager()
        eventScheduler = EventScheduler(
            preferencesManager: preferencesManager, linkParser: linkParser,
        )
        eventScheduler.setNotificationManager(notificationManager)
        if let overlayManagerOverride {
            overlayManager = overlayManagerOverride
        } else {
            overlayManager = OverlayManager(
                preferencesManager: preferencesManager,
                eventScheduler: eventScheduler,
                soundManager: soundManager,
                focusModeManager: focusModeManager,
                linkParser: linkParser,
                themeManager: themeManager,
            )
        }
        menuBarPreviewManager = MenuBarPreviewManager(preferencesManager: preferencesManager)
        shortcutsManager = ShortcutsManager(
            overlayManager: overlayManager, linkParser: linkParser,
        )
        healthMonitor = HealthMonitor(
            calendarService: calendarService,
            overlayManager: overlayManager,
        )
        if let meetingDetailsPopupManagerOverride {
            meetingDetailsPopupManager = meetingDetailsPopupManagerOverride
        } else {
            meetingDetailsPopupManager = MeetingDetailsPopupManager(
                themeManager: themeManager,
                databaseManager: databaseManager,
            )
        }

        activationPolicyManager = ActivationPolicyManager()

        logger.info("Service graph wired successfully")
        AppDiagnostics.record(component: "ServiceContainer", phase: "wired") {
            [
                "services": "database,calendar,overlay,scheduler,health,notifications,shortcuts,menuBar,meetingDetails",
                "databaseType": "\(type(of: databaseManager))",
            ]
        }
    }
}
