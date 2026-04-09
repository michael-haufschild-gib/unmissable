import Foundation
import OSLog

/// Owns the construction and lifecycle of all application services.
/// AppState reads from this container instead of constructing services directly.
@MainActor
final class ServiceContainer {
    private let logger = Logger(category: "ServiceContainer")
    let databaseManager: any DatabaseManaging
    let linkParser: LinkParser
    let themeManager: ThemeManager
    let preferencesManager: PreferencesManager
    let soundManager: SoundManager
    let calendarService: CalendarService
    let overlayManager: any OverlayManaging
    let eventScheduler: EventScheduler
    let shortcutsManager: ShortcutsManager
    let healthMonitor: HealthMonitor
    let notificationManager: NotificationManager
    let menuBarPreviewManager: MenuBarPreviewManager
    let meetingDetailsPopupManager: any MeetingDetailsPopupManaging
    let activationPolicyManager: ActivationPolicyManager
    let systemSleepObserver: SystemSleepObserver
    let networkMonitor: NetworkMonitor

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

        systemSleepObserver = SystemSleepObserver()
        networkMonitor = NetworkMonitor()

        preferencesManager = preferencesManagerOverride ?? PreferencesManager(themeManager: themeManager)
        soundManager = SoundManager(preferencesManager: preferencesManager)
        calendarService = CalendarService(
            preferencesManager: preferencesManager,
            databaseManager: databaseManager,
            linkParser: linkParser,
            networkMonitor: networkMonitor,
            sleepObserver: systemSleepObserver,
        )
        notificationManager = NotificationManager()
        eventScheduler = EventScheduler(
            preferencesManager: preferencesManager,
            linkParser: linkParser,
            sleepObserver: systemSleepObserver,
        )
        eventScheduler.setNotificationManager(notificationManager)
        if let overlayManagerOverride {
            overlayManager = overlayManagerOverride
        } else {
            overlayManager = OverlayManager(
                preferencesManager: preferencesManager,
                eventScheduler: eventScheduler,
                soundManager: soundManager,
                notificationManager: notificationManager,
                linkParser: linkParser,
                themeManager: themeManager,
            )
        }
        menuBarPreviewManager = MenuBarPreviewManager(
            preferencesManager: preferencesManager,
            sleepObserver: systemSleepObserver,
        )
        shortcutsManager = ShortcutsManager(
            overlayManager: overlayManager, linkParser: linkParser,
        )
        shortcutsManager.setPreferencesManager(preferencesManager)
        healthMonitor = HealthMonitor(
            calendarService: calendarService,
            overlayManager: overlayManager,
            sleepObserver: systemSleepObserver,
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
                "services": "database,calendar,overlay,scheduler,health,notifications," +
                    "shortcuts,menuBar,meetingDetails,sleepObserver,networkMonitor",
                "databaseType": "\(type(of: databaseManager))",
            ]
        }
    }
}
