import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(category: "AppState")

    // MARK: - Services (from DI container)

    private let services: ServiceContainer
    private lazy var preferencesWindowManager = PreferencesWindowManager(appState: self)
    private lazy var onboardingWindowManager = OnboardingWindowManager(appState: self)

    @Published
    var databaseError: String?

    private var cancellables = Set<AnyCancellable>()

    init(services: ServiceContainer = ServiceContainer(databaseManager: DatabaseManager())) {
        self.services = services

        setupBindings()
        checkInitialState()
    }

    private func setupBindings() {
        let calendarService = services.calendarService
        let preferencesManager = services.preferencesManager

        // Update menu bar preview when events or started events change.
        // Combine both arrays so getNextMeeting() can detect in-progress meetings.
        calendarService.$events
            .sink { [weak self] events in
                guard let self else { return }
                let started = services.calendarService.startedEvents
                services.menuBarPreviewManager.updateEvents(started + events)
            }
            .store(in: &cancellables)

        calendarService.$startedEvents
            .sink { [weak self] startedEvents in
                guard let self else { return }
                let upcoming = services.calendarService.events
                services.menuBarPreviewManager.updateEvents(startedEvents + upcoming)
            }
            .store(in: &cancellables)

        // Observe preference changes to force immediate UI updates
        preferencesManager.$menuBarDisplayMode
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Show preferences when app is reopened with no visible windows
        NotificationCenter.default.publisher(for: .showPreferences)
            .sink { [weak self] _ in
                self?.showPreferences()
            }
            .store(in: &cancellables)

        // Reschedule events after sync updates
        calendarService.eventsUpdated
            .sink { [weak self] in
                self?.rescheduleEventsAfterSync()
            }
            .store(in: &cancellables)
    }

    private func rescheduleEventsAfterSync() {
        let events = services.calendarService.events
        logger.debug("Rescheduling \(events.count) events after sync")

        Task {
            await loadAlertOverrides()
            loadCalendarAlertModes()
            services.eventScheduler.startScheduling(
                events: events,
                overlayManager: services.overlayManager,
            )
        }
    }

    private func checkInitialState() {
        logger.debug("Checking initial state")

        // Sync login item preference with system state (user may have
        // changed it in System Settings > General > Login Items)
        services.preferencesManager.syncLoginItemWithSystem()

        // First-time users see the onboarding flow; returning users get the
        // accessibility-permission prompt (no-op if already granted).
        if !services.preferencesManager.hasCompletedOnboarding {
            logger.info("First launch detected — showing onboarding")
            onboardingWindowManager.showOnboarding()
        } else {
            requestAccessibilityPermission()
        }

        Task {
            if let dbError = await services.databaseManager.initializationError {
                logger.error("Database initialization failed: \(dbError)")
                databaseError = dbError
            }

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

    func retryDatabaseInitialization() async {
        logger.info("Retrying database initialization")
        let error = await services.databaseManager.reinitialize()
        if let error {
            logger.error("Database retry failed: \(error)")
            databaseError = error
        } else {
            logger.info("Database retry succeeded")
            databaseError = nil
            await services.calendarService.checkConnectionStatus()
            if services.calendarService.isConnected {
                await startPeriodicSync()
            }
        }
    }

    func syncNow() async {
        logger.debug("Manual sync requested")
        await services.calendarService.syncEvents()
    }

    func updateCalendarSelection(_ calendarId: String, isSelected: Bool) {
        services.calendarService.updateCalendarSelection(calendarId, isSelected: isSelected)
    }

    /// Updates the alert mode for a calendar and propagates to the scheduler.
    /// Requests notification permission when first switching to `.notification` mode.
    func updateCalendarAlertMode(_ calendarId: String, alertMode: AlertMode) {
        if alertMode == .notification {
            Task {
                await services.notificationManager.requestPermission()
            }
        }
        services.calendarService.updateCalendarAlertMode(calendarId, alertMode: alertMode)
        loadCalendarAlertModes()
    }

    // MARK: - Service Access (only services required by SwiftUI environment)

    var preferences: PreferencesManager {
        services.preferencesManager
    }

    var linkParser: LinkParser {
        services.linkParser
    }

    var themeManager: ThemeManager {
        services.themeManager
    }

    var menuBarPreview: MenuBarPreviewManager {
        services.menuBarPreviewManager
    }

    var calendar: CalendarService {
        services.calendarService
    }

    // MARK: - Update Management

    var canCheckForUpdates: Bool {
        services.updateManager.canCheckForUpdates
    }

    func checkForUpdates() {
        services.updateManager.checkForUpdates()
    }

    func showPreferences() {
        preferencesWindowManager.showPreferences()
    }

    func showMeetingDetails(for event: Event, relativeTo parentWindow: NSWindow? = nil) {
        services.meetingDetailsPopupManager.showPopup(for: event, relativeTo: parentWindow)
    }

    // MARK: - Onboarding

    /// Marks onboarding as complete, closes the onboarding window, and requests
    /// the accessibility permission that was deferred until after onboarding.
    func completeOnboarding() {
        logger.info("Onboarding completed")
        services.preferencesManager.setHasCompletedOnboarding(true)
        onboardingWindowManager.close()
        requestAccessibilityPermission()
    }

    /// Shows a demo overlay with a synthetic event so the user can experience
    /// the core feature during onboarding.
    func showDemoOverlay() {
        guard let demoURL = URL(string: "https://meet.google.com/abc-defg-hij") else {
            logger.error("Failed to create demo meeting URL")
            return
        }

        let demoEvent = Event(
            id: "onboarding-demo",
            title: "Team Standup",
            startDate: Date().addingTimeInterval(DemoOverlay.startDelaySeconds),
            endDate: Date().addingTimeInterval(DemoOverlay.endDelaySeconds),
            organizer: "you@company.com",
            calendarId: "demo",
            links: [demoURL],
        )

        logger.info("Showing demo overlay for onboarding")
        services.overlayManager.showOverlay(for: demoEvent, fromSnooze: false)
    }

    private enum DemoOverlay {
        static let startDelaySeconds: TimeInterval = 120
        static let endDelaySeconds: TimeInterval = 1920
    }

    /// Requests accessibility permission from the system.
    /// Prompts the user only if permission has not already been granted.
    private func requestAccessibilityPermission() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessibilityEnabled {
            logger.warning("Accessibility permissions not granted")
        }
    }

    // MARK: - Alert Overrides

    /// Sets or clears a per-event alert timing override.
    /// Passing `nil` removes the override (reverts to default timing).
    /// Passing `0` suppresses all alerts for the event.
    func setAlertOverride(for eventId: String, minutes: Int?) async {
        do {
            try await services.databaseManager.saveAlertOverride(
                eventId: eventId,
                minutes: minutes,
            )
            await loadAlertOverrides()
            logger.info(
                "Alert override set for event \(eventId): \(minutes.map(String.init) ?? "default")",
            )
        } catch {
            logger.error("Failed to save alert override: \(error.localizedDescription)")
        }
    }

    /// Fetches the alert override for a single event from the database.
    func alertOverride(for eventId: String) async -> Int? {
        do {
            return try await services.databaseManager.fetchAlertOverride(for: eventId)
        } catch {
            logger.error("Failed to fetch alert override: \(error.localizedDescription)")
            return nil
        }
    }

    /// Batch-loads all alert overrides from the database and pushes them to the scheduler.
    private func loadAlertOverrides() async {
        do {
            let overrides = try await services.databaseManager.fetchAllAlertOverrides()
            services.eventScheduler.updateAlertOverrides(overrides)
        } catch {
            logger.error("Failed to load alert overrides: \(error.localizedDescription)")
        }
    }

    /// Reads alert modes from in-memory calendars and pushes them to the scheduler.
    private func loadCalendarAlertModes() {
        let modes = Dictionary(
            uniqueKeysWithValues: services.calendarService.calendars.map { ($0.id, $0.alertMode) },
        )
        services.eventScheduler.updateCalendarAlertModes(modes)
    }

    private func startPeriodicSync() async {
        await services.calendarService.checkConnectionStatus()
        await loadAlertOverrides()
        loadCalendarAlertModes()

        services.eventScheduler.startScheduling(
            events: services.calendarService.events,
            overlayManager: services.overlayManager,
        )

        if services.calendarService.isConnected {
            services.calendarService.primarySync?.startPeriodicSync()
        }
    }
}
