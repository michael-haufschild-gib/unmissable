import AppKit
import Combine
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppState {
    private let logger = Logger(category: "AppState")

    // MARK: - Services (from DI container)

    @ObservationIgnored
    private let services: ServiceContainer
    @ObservationIgnored
    private(set) lazy var preferencesWindowManager = PreferencesWindowManager(appState: self)
    @ObservationIgnored
    private(set) lazy var onboardingWindowManager = OnboardingWindowManager(appState: self)

    var databaseError: String?

    /// In-memory cache of per-event alert overrides, keyed by event ID.
    /// Populated by loadAlertOverrides() and read by EventRow to avoid N+1 DB queries.
    private(set) var alertOverrides: [String: Int] = [:]

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored
    private var rescheduleTask: Task<Void, Never>?

    /// True when running under XCTest / Swift Testing — gates all side-effecting
    /// launch work (window creation, NSApp API calls, AX prompts, login items).
    @ObservationIgnored
    private let isTestEnvironment: Bool

    init(
        services: ServiceContainer? = nil,
        isTestEnvironment: Bool = false,
    ) {
        if let services {
            self.services = services
        } else if isTestEnvironment {
            // Safety net for the @main entry point during test runs.
            // Use a temp database so we never touch the production DB.
            // This AppState is unused — each test creates its own.
            let tempDB = FileManager.default.temporaryDirectory
                .appendingPathComponent("unmissable-test-host-\(UUID().uuidString).db")
            self.services = ServiceContainer(databaseManager: DatabaseManager(databaseURL: tempDB))
        } else {
            self.services = ServiceContainer(databaseManager: DatabaseManager())
        }
        self.isTestEnvironment = isTestEnvironment

        // Always install in-process observers so menuBarPreviewManager and
        // scheduling stay in sync even in tests. Side-effectful launch work
        // (window creation, NSApp activation, AX prompts) is gated in
        // observeAppLaunch() and checkInitialState() via isTestEnvironment.
        setupBindings()

        guard !isTestEnvironment else { return }
        observeAppLaunch()
    }

    private func setupBindings() {
        // Update menu bar preview when events or started events change.
        observeCalendarEventChanges()

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

    /// Whether `checkInitialState()` has already been called.
    /// Prevents double invocation from both the notification and the fallback path.
    @ObservationIgnored
    private var didCheckInitialState = false

    /// Defers initial state checks until after NSApplication finishes launching.
    ///
    /// When `AppState` is created eagerly during `@State` initialization it runs
    /// before `applicationDidFinishLaunching`, so we subscribe to the notification.
    /// When `AppState` is created lazily (e.g. from a `.task` modifier) the
    /// notification may have already fired. To cover both cases we subscribe AND
    /// schedule a fallback on the next run-loop turn — whichever fires first wins,
    /// the `didCheckInitialState` guard prevents double invocation.
    private func observeAppLaunch() {
        NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.runInitialStateOnce()
            }
            .store(in: &cancellables)

        // Fallback: if the notification already fired before we subscribed,
        // this fires on the next run-loop turn instead.
        DispatchQueue.main.async { [weak self] in
            self?.runInitialStateOnce()
        }
    }

    private func runInitialStateOnce() {
        guard !didCheckInitialState else { return }
        didCheckInitialState = true
        checkInitialState()
    }

    /// Observes both `events` and `startedEvents` in a single tracking block.
    /// When either changes (e.g. after a sync), the menu bar preview is updated once
    /// instead of twice.
    private func observeCalendarEventChanges() {
        withObservationTracking {
            _ = services.calendarService.events
            _ = services.calendarService.startedEvents
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let events = services.calendarService.events
                let started = services.calendarService.startedEvents
                services.menuBarPreviewManager.updateEvents(started + events)
                observeCalendarEventChanges()
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

        rescheduleTask?.cancel()
        rescheduleTask = Task {
            guard !Task.isCancelled else { return }
            await loadAlertOverrides()
            guard !Task.isCancelled else { return }
            loadCalendarAlertModes()
            services.eventScheduler.startScheduling(
                events: events,
                overlayManager: services.overlayManager,
            )
        }
    }

    func checkInitialState() {
        let flow = AppDiagnostics.startFlow("initialState", component: "AppState")
        logger.debug("Checking initial state")

        guard !isTestEnvironment else {
            logger.info("Test environment — skipping side-effectful launch work")
            AppDiagnostics.endFlow(flow, component: "AppState") { [:] }
            return
        }

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

            if AppRuntime.injectTestEvents {
                // Events are already injected in CalendarService.init().
                // Do NOT start the event scheduler — UI tests control overlay
                // display explicitly.
                if AppRuntime.showTestMeetingDetails,
                   let firstEvent = services.calendarService.events.first
                {
                    showMeetingDetails(for: firstEvent)
                }
                AppDiagnostics.endFlow(flow, component: "AppState") {
                    ["uiTestEvents": "injected"]
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

    var activationPolicyManager: ActivationPolicyManager {
        services.activationPolicyManager
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

    /// Marks onboarding as complete and requests the accessibility permission
    /// that was deferred until after onboarding. Idempotent — safe to call
    /// multiple times (e.g. from both the "Done" button and the window-close
    /// delegate).
    func markOnboardingComplete() {
        guard !services.preferencesManager.hasCompletedOnboarding else { return }
        logger.info("Onboarding completed")
        services.preferencesManager.setHasCompletedOnboarding(true)
        requestAccessibilityPermission()
    }

    /// Marks onboarding as complete and closes the onboarding window.
    func completeOnboarding() {
        markOnboardingComplete()
        onboardingWindowManager.close()
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
        guard !AppRuntime.isUITesting else {
            logger.info("Skipping accessibility permission prompt in UI testing mode")
            return
        }

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
                "Alert override set for event \(PrivacyUtils.redactedEventId(eventId)): \(minutes.map(String.init) ?? "default")",
            )
        } catch {
            logger.error("Failed to save alert override: \(PrivacyUtils.redactedError(error))")
        }
    }

    /// Batch-loads all alert overrides from the database and pushes them to the scheduler.
    private func loadAlertOverrides() async {
        do {
            let overrides = try await services.databaseManager.fetchAllAlertOverrides()
            alertOverrides = overrides
            services.eventScheduler.updateAlertOverrides(overrides)
        } catch {
            logger.error("Failed to load alert overrides: \(PrivacyUtils.redactedError(error))")
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
