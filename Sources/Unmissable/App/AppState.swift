import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "AppState")

    // Published properties for UI binding
    @Published var isConnectedToCalendar = false
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncTime: Date?
    @Published var upcomingEvents: [Event] = []
    @Published var startedEvents: [Event] = []
    @Published var activeOverlay: Event?
    @Published var userEmail: String?
    @Published var calendars: [CalendarInfo] = []
    @Published var authError: String?
    @Published var healthStatus: HealthStatus = .healthy

    // Menu bar preview properties (mirrored from MenuBarPreviewManager)
    @Published var menuBarText: String?
    @Published var shouldShowIcon: Bool = true

    // Services
    private let calendarService: CalendarService
    private let preferencesManager = PreferencesManager()
    private let overlayManager: OverlayManager
    private let eventScheduler: EventScheduler
    private let shortcutsManager = ShortcutsManager()
    private let focusModeManager: FocusModeManager
    private let healthMonitor = HealthMonitor()
    private let menuBarPreviewManager: MenuBarPreviewManager
    private let meetingDetailsPopupManager = MeetingDetailsPopupManager()
    private lazy var preferencesWindowManager = PreferencesWindowManager(appState: self)

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Initialize services in dependency order
        focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        calendarService = CalendarService(preferencesManager: preferencesManager)
        overlayManager = OverlayManager(
            preferencesManager: preferencesManager, focusModeManager: focusModeManager
        )
        eventScheduler = EventScheduler(preferencesManager: preferencesManager)
        menuBarPreviewManager = MenuBarPreviewManager(preferencesManager: preferencesManager)

        // Connect OverlayManager to EventScheduler for proper snooze functionality
        overlayManager.setEventScheduler(eventScheduler)

        setupBindings()
        checkInitialState()

        // Setup shortcuts after managers are ready
        shortcutsManager.setup(overlayManager: overlayManager)

        // Setup health monitoring
        healthMonitor.setup(
            calendarService: calendarService,
            syncManager: calendarService.syncManagerPublic,
            overlayManager: overlayManager
        )
    }

    private func setupBindings() {
        // Observe calendar connection status
        calendarService.$isConnected
            .assign(to: \.isConnectedToCalendar, on: self)
            .store(in: &cancellables)

        // Observe sync status
        calendarService.$syncStatus
            .assign(to: \.syncStatus, on: self)
            .store(in: &cancellables)

        // Observe upcoming events
        calendarService.$events
            .assign(to: \.upcomingEvents, on: self)
            .store(in: &cancellables)

        // Observe started events
        calendarService.$startedEvents
            .assign(to: \.startedEvents, on: self)
            .store(in: &cancellables)

        // Update menu bar preview when events change
        calendarService.$events
            .sink { [weak self] events in
                self?.menuBarPreviewManager.updateEvents(events)
            }
            .store(in: &cancellables)

        // Update menu bar preview when started events change (for proper next meeting calculation)
        calendarService.$startedEvents
            .sink { [weak self] _ in
                guard let self else { return }
                // Refresh with all upcoming events to recalculate next meeting
                menuBarPreviewManager.updateEvents(upcomingEvents)
            }
            .store(in: &cancellables)

        // Observe calendars
        calendarService.$calendars
            .assign(to: \.calendars, on: self)
            .store(in: &cancellables)

        // Observe user email
        calendarService.oauth2Service.$userEmail
            .assign(to: \.userEmail, on: self)
            .store(in: &cancellables)

        // Observe auth errors
        calendarService.oauth2Service.$authorizationError
            .assign(to: \.authError, on: self)
            .store(in: &cancellables)

        // Observe active overlay
        overlayManager.$activeEvent
            .assign(to: \.activeOverlay, on: self)
            .store(in: &cancellables)

        // Observe health status
        healthMonitor.$healthStatus
            .assign(to: \.healthStatus, on: self)
            .store(in: &cancellables)

        // Mirror menu bar preview manager properties AND observe preferences directly
        menuBarPreviewManager.$menuBarText
            .assign(to: \.menuBarText, on: self)
            .store(in: &cancellables)

        menuBarPreviewManager.$shouldShowIcon
            .assign(to: \.shouldShowIcon, on: self)
            .store(in: &cancellables)

        // ALSO directly observe preference changes to force immediate UI updates
        preferencesManager.$menuBarDisplayMode
            .sink { [weak self] _ in
                // Force update the mirrored properties immediately when preferences change
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Set up callback to reschedule events after sync updates
        setupEventReschedulingCallback()
    }

    private func setupEventReschedulingCallback() {
        calendarService.onEventsUpdated = { [weak self] in
            await self?.rescheduleEventsAfterSync()
        }
    }

    private func rescheduleEventsAfterSync() async {
        logger.info("🔄 Rescheduling events after sync completion...")
        logger.info("📋 Events available for rescheduling: \(upcomingEvents.count)")

        // List the first few events for debugging
        for (index, event) in upcomingEvents.prefix(3).enumerated() {
            logger.info("  Event \(index + 1): \(event.title) at \(event.startDate)")
        }

        await eventScheduler.startScheduling(
            events: upcomingEvents,
            overlayManager: overlayManager
        )
        logger.info("✅ Events rescheduled with updated times")
    }

    private func checkInitialState() {
        logger.info("🔍 AppState checking initial state...")
        Task {
            await calendarService.checkConnectionStatus()
            logger.info("📡 Connection status checked - isConnected: \(self.isConnectedToCalendar)")
            if self.isConnectedToCalendar {
                logger.info("🔄 Starting periodic sync due to existing connection")
                await self.startPeriodicSync()
            } else {
                logger.info("❌ Not connected to calendar - sync not started")
            }
        }
    }

    // MARK: - Public Interface

    func connectToCalendar() async {
        logger.info("Initiating calendar connection")
        await calendarService.connect()

        if isConnectedToCalendar {
            await startPeriodicSync()
        }
    }

    func disconnectFromCalendar() async {
        logger.info("Disconnecting from calendar")
        await calendarService.disconnect()
        eventScheduler.stopScheduling()
    }

    func syncNow() async {
        logger.info("Manual sync requested")
        await calendarService.syncEvents()
    }

    func updateCalendarSelection(_ calendarId: String, isSelected: Bool) {
        calendarService.updateCalendarSelection(calendarId, isSelected: isSelected)
    }

    // MARK: - Public Services Access

    var calendarServicePublic: CalendarService {
        calendarService
    }

    var preferencesManagerPublic: PreferencesManager {
        preferencesManager
    }

    var shortcutsManagerPublic: ShortcutsManager {
        shortcutsManager
    }

    var focusModeManagerPublic: FocusModeManager {
        focusModeManager
    }

    var healthMonitorPublic: HealthMonitor {
        healthMonitor
    }

    var menuBarPreviewManagerPublic: MenuBarPreviewManager {
        menuBarPreviewManager
    }

    func showPreferences() {
        preferencesWindowManager.showPreferences()
    }

    func showMeetingDetails(for event: Event, relativeTo parentWindow: NSWindow? = nil) {
        meetingDetailsPopupManager.showPopup(for: event, relativeTo: parentWindow)
    }

    private func startPeriodicSync() async {
        logger.info("🚀 AppState.startPeriodicSync() called")

        // CRITICAL FIX: Load cached data first to ensure we have events to schedule
        logger.info("📥 Loading cached events before scheduling...")
        await calendarService.checkConnectionStatus() // This calls loadCachedData internally

        logger.info("📋 Events available for scheduling: \(upcomingEvents.count)")

        // Start both event scheduling and calendar sync
        await eventScheduler.startScheduling(
            events: upcomingEvents,
            overlayManager: overlayManager
        )

        // Also start periodic calendar sync if connected
        if isConnectedToCalendar {
            logger.info("📅 Calling SyncManager.startPeriodicSync()")
            calendarService.syncManagerPublic.startPeriodicSync()
        } else {
            logger.info("❌ Not connected - skipping SyncManager.startPeriodicSync()")
        }
    }
}

enum SyncStatus: Equatable {
    case idle
    case syncing
    case offline
    case error(String)

    var description: String {
        switch self {
        case .idle:
            "Ready"
        case .syncing:
            "Syncing..."
        case .offline:
            "Offline"
        case let .error(message):
            "Error: \(message)"
        }
    }
}
