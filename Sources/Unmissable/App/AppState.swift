import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "AppState")

    // MARK: - Services (from DI container)

    private let services: ServiceContainer
    private lazy var preferencesWindowManager = PreferencesWindowManager(appState: self)

    private var cancellables = Set<AnyCancellable>()

    init(services: ServiceContainer = ServiceContainer()) {
        self.services = services

        setupBindings()
        checkInitialState()
    }

    private func setupBindings() {
        let calendarService = services.calendarService
        let preferencesManager = services.preferencesManager

        // Update menu bar preview when events change
        calendarService.$events
            .sink { [weak self] events in
                self?.services.menuBarPreviewManager.updateEvents(events)
            }
            .store(in: &cancellables)

        // Update menu bar preview when started events change
        calendarService.$startedEvents
            .sink { [weak self] _ in
                guard let self else { return }
                services.menuBarPreviewManager.updateEvents(
                    services.calendarService.events
                )
            }
            .store(in: &cancellables)

        // Observe preference changes to force immediate UI updates
        preferencesManager.$menuBarDisplayMode
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Set up callback to reschedule events after sync updates
        setupEventReschedulingCallback()
    }

    private func setupEventReschedulingCallback() {
        services.calendarService.onEventsUpdated = { [weak self] in
            self?.rescheduleEventsAfterSync()
        }
    }

    private func rescheduleEventsAfterSync() {
        let events = services.calendarService.events
        logger.debug("Rescheduling \(events.count) events after sync")

        services.eventScheduler.startScheduling(
            events: events,
            overlayManager: services.overlayManager
        )
    }

    private func checkInitialState() {
        logger.debug("Checking initial state")
        Task {
            await services.calendarService.checkConnectionStatus()
            if services.calendarService.isConnected {
                logger.info("Calendar connected, starting sync")
                await self.startPeriodicSync()
            } else {
                logger.debug("Not connected to calendar")
            }
        }
    }

    // MARK: - Public Interface

    func connectToCalendar(provider: CalendarProviderType) async {
        logger.info("Initiating \(provider.rawValue) calendar connection")
        await services.calendarService.connect(provider: provider)

        if services.calendarService.isConnected {
            await startPeriodicSync()
        }
    }

    func disconnectFromCalendar(provider: CalendarProviderType) async {
        logger.info("Disconnecting from \(provider.rawValue) calendar")
        await services.calendarService.disconnect(provider: provider)

        if !services.calendarService.isConnected {
            services.eventScheduler.stopScheduling()
        }
    }

    func disconnectAll() async {
        logger.info("Disconnecting from all calendars")
        await services.calendarService.disconnectAll()
        services.eventScheduler.stopScheduling()
    }

    var connectedProviders: Set<CalendarProviderType> {
        services.calendarService.connectedProviders
    }

    func syncNow() async {
        logger.debug("Manual sync requested")
        await services.calendarService.syncEvents()
    }

    func updateCalendarSelection(_ calendarId: String, isSelected: Bool) {
        services.calendarService.updateCalendarSelection(calendarId, isSelected: isSelected)
    }

    // MARK: - Service Access

    var preferences: PreferencesManager {
        services.preferencesManager
    }

    var shortcuts: ShortcutsManager {
        services.shortcutsManager
    }

    var focusMode: FocusModeManager {
        services.focusModeManager
    }

    var health: HealthMonitor {
        services.healthMonitor
    }

    var menuBarPreview: MenuBarPreviewManager {
        services.menuBarPreviewManager
    }

    var calendar: CalendarService {
        services.calendarService
    }

    var updater: UpdateManager {
        services.updateManager
    }

    func showPreferences() {
        preferencesWindowManager.showPreferences()
    }

    func showMeetingDetails(for event: Event, relativeTo parentWindow: NSWindow? = nil) {
        services.meetingDetailsPopupManager.showPopup(for: event, relativeTo: parentWindow)
    }

    private func startPeriodicSync() async {
        await services.calendarService.checkConnectionStatus()

        services.eventScheduler.startScheduling(
            events: services.calendarService.events,
            overlayManager: services.overlayManager
        )

        if services.calendarService.isConnected {
            services.calendarService.sync?.startPeriodicSync()
        }
    }
}
