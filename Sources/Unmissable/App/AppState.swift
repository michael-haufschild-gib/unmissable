import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "AppState")

    // MARK: - View State (mirrored from child services for SwiftUI observation)

    @Published
    var isConnectedToCalendar = false
    @Published
    var syncStatus: SyncStatus = .idle
    @Published
    var upcomingEvents: [Event] = []
    @Published
    var startedEvents: [Event] = []
    @Published
    var userEmail: String?
    @Published
    var calendars: [CalendarInfo] = []
    @Published
    var authError: String?
    @Published
    var menuBarText: String?
    @Published
    var shouldShowIcon: Bool = true

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
        let menuBarPreviewManager = services.menuBarPreviewManager
        let preferencesManager = services.preferencesManager

        // Observe calendar connection status
        calendarService.$isConnected
            .sink { [weak self] in self?.isConnectedToCalendar = $0 }
            .store(in: &cancellables)

        // Observe sync status
        calendarService.$syncStatus
            .sink { [weak self] in self?.syncStatus = $0 }
            .store(in: &cancellables)

        // Observe upcoming events
        calendarService.$events
            .sink { [weak self] in self?.upcomingEvents = $0 }
            .store(in: &cancellables)

        // Observe started events
        calendarService.$startedEvents
            .sink { [weak self] in self?.startedEvents = $0 }
            .store(in: &cancellables)

        // Update menu bar preview when events change
        calendarService.$events
            .sink { [weak self] events in
                self?.services.menuBarPreviewManager.updateEvents(events)
            }
            .store(in: &cancellables)

        // Update menu bar preview when started events change (for proper next meeting calculation)
        calendarService.$startedEvents
            .sink { [weak self] _ in
                guard let self else { return }
                services.menuBarPreviewManager.updateEvents(upcomingEvents)
            }
            .store(in: &cancellables)

        // Observe calendars
        calendarService.$calendars
            .sink { [weak self] in self?.calendars = $0 }
            .store(in: &cancellables)

        // Observe user email
        calendarService.$userEmail
            .sink { [weak self] in self?.userEmail = $0 }
            .store(in: &cancellables)

        // Observe auth errors
        calendarService.$authError
            .sink { [weak self] in self?.authError = $0 }
            .store(in: &cancellables)

        // Mirror menu bar preview manager properties
        menuBarPreviewManager.$menuBarText
            .sink { [weak self] in self?.menuBarText = $0 }
            .store(in: &cancellables)

        menuBarPreviewManager.$shouldShowIcon
            .sink { [weak self] in self?.shouldShowIcon = $0 }
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
        logger.debug("Rescheduling \(self.upcomingEvents.count) events after sync")

        services.eventScheduler.startScheduling(
            events: upcomingEvents,
            overlayManager: services.overlayManager
        )
    }

    private func checkInitialState() {
        logger.debug("Checking initial state")
        Task {
            await services.calendarService.checkConnectionStatus()
            if self.isConnectedToCalendar {
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

        if isConnectedToCalendar {
            await startPeriodicSync()
        }
    }

    func disconnectFromCalendar(provider: CalendarProviderType) {
        logger.info("Disconnecting from \(provider.rawValue) calendar")
        services.calendarService.disconnect(provider: provider)

        if !isConnectedToCalendar {
            services.eventScheduler.stopScheduling()
        }
    }

    func disconnectAll() {
        logger.info("Disconnecting from all calendars")
        services.calendarService.disconnectAll()
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
            events: upcomingEvents,
            overlayManager: services.overlayManager
        )

        if isConnectedToCalendar {
            services.calendarService.sync?.startPeriodicSync()
        }
    }
}
