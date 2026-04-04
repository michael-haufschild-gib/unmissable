import AppKit
import Combine
import Foundation
import Observation
import OSLog

@Observable
final class AppState {
    private let logger = Logger(category: "AppState")

    // MARK: - Services (from DI container)

    @ObservationIgnored
    private let services: ServiceContainer
    @ObservationIgnored
    private lazy var preferencesWindowManager = PreferencesWindowManager(appState: self)
    @ObservationIgnored
    private lazy var onboardingWindowManager = OnboardingWindowManager(appState: self)

    var databaseError: String?

    /// In-memory cache of per-event alert overrides, keyed by event ID.
    /// Populated by loadAlertOverrides() and read by EventRow to avoid N+1 DB queries.
    private(set) var alertOverrides: [String: Int] = [:]

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    init(services: ServiceContainer = ServiceContainer(databaseManager: DatabaseManager())) {
        self.services = services

        setupBindings()
        checkInitialState()
    }

    private func setupBindings() {
        // Update menu bar preview when events or started events change.
        observeCalendarEvents()
        observeStartedEvents()

        // Show preferences when app is reopened with no visible windows
        NotificationCenter.default.publisher(for: .showPreferences)
            .sink { [weak self] _ in
                self?.showPreferences()
            }
            .store(in: &cancellables)

        // Reschedule events after sync updates
        services.calendarService.eventsUpdated
            .sink { [weak self] in
                self?.rescheduleEventsAfterSync()
            }
            .store(in: &cancellables)
    }

    private func observeCalendarEvents() {
        withObservationTracking {
            _ = services.calendarService.events
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let events = services.calendarService.events
                let started = services.calendarService.startedEvents
                services.menuBarPreviewManager.updateEvents(started + events)
                self.observeCalendarEvents()
            }
        }
    }

    private func observeStartedEvents() {
        withObservationTracking {
            _ = services.calendarService.startedEvents
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let upcoming = services.calendarService.events
                let startedEvents = services.calendarService.startedEvents
                services.menuBarPreviewManager.updateEvents(startedEvents + upcoming)
                self.observeStartedEvents()
            }
        }
    }

    private func rescheduleEventsAfterSync() {
        let events = services.calendarService.events
        logger.debug("Rescheduling \(events.count) events after sync")
        AppDiagnostics.record(component: "AppState", phase: "rescheduleAfterSync") {
            [
                "eventCount": "\(events.count)",
                "overrideCount": "\(self.alertOverrides.count)",
            ]
        }

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
        let flow = AppDiagnostics.startFlow("initialState", component: "AppState")
        logger.debug("Checking initial state")

        // Register notification categories now that the app bundle proxy exists.
        // Cannot be done in ServiceContainer.init because UNUserNotificationCenter
        // requires a bundle proxy that isn't available until the app is running.
        services.notificationManager.registerCategories()

        // Sync login item preference with system state (user may have
        // changed it in System Settings > General > Login Items)
        services.preferencesManager.syncLoginItemWithSystem()

        // First-time users see the onboarding flow; returning users get the
        // accessibility-permission prompt (no-op if already granted).
        let hasCompletedOnboarding = services.preferencesManager.hasCompletedOnboarding
        if !hasCompletedOnboarding {
            logger.info("First launch detected — showing onboarding")
            onboardingWindowManager.showOnboarding()
        } else {
            requestAccessibilityPermission()
        }

        AppDiagnostics.record(component: "AppState", phase: "initialChecks") {
            ["onboardingComplete": "\(hasCompletedOnboarding)"]
        }

        Task {
            if let dbError = await services.databaseManager.initializationError {
                logger.error("Database initialization failed: \(dbError)")
                databaseError = dbError
                AppDiagnostics.endFlow(flow, component: "AppState", outcome: .failure) {
                    ["reason": "dbInitFailed", "error": PrivacyUtils.redactedErrorString(dbError)]
                }
                return
            }

            await services.calendarService.checkConnectionStatus()
            let isConnected = services.calendarService.isConnected
            let providerCount = services.calendarService.connectedProviders.count
            if isConnected {
                logger.info("Calendar connected, starting sync")
                await self.startPeriodicSync()
            } else {
                logger.debug("Not connected to calendar")
            }

            AppDiagnostics.endFlow(flow, component: "AppState") {
                [
                    "calendarConnected": "\(isConnected)",
                    "providers": "\(providerCount)",
                ]
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
    func setAlertOverride(for eventId: String, calendarId: String, minutes: Int?) async {
        do {
            try await services.databaseManager.saveAlertOverride(
                eventId: eventId,
                calendarId: calendarId,
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

    /// Batch-loads all alert overrides from the database and pushes them to the scheduler.
    private func loadAlertOverrides() async {
        do {
            let overrides = try await services.databaseManager.fetchAllAlertOverrides()
            alertOverrides = overrides
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
        let flow = AppDiagnostics.startFlow("startPeriodicSync", component: "AppState")

        await services.calendarService.checkConnectionStatus()
        await loadAlertOverrides()
        loadCalendarAlertModes()

        let eventCount = services.calendarService.events.count
        services.eventScheduler.startScheduling(
            events: services.calendarService.events,
            overlayManager: services.overlayManager,
        )

        let isConnected = services.calendarService.isConnected
        if isConnected {
            services.calendarService.startAllPeriodicSync()
        }

        AppDiagnostics.endFlow(flow, component: "AppState") {
            [
                "events": "\(eventCount)",
                "connected": "\(isConnected)",
                "overrides": "\(self.alertOverrides.count)",
            ]
        }
    }
}
