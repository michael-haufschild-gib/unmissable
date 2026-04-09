import Combine
import EventKit
import Foundation
import Observation
import OSLog

/// Representation of a connected calendar provider backend.
@MainActor
struct ProviderBackend {
    let type: CalendarProviderType
    let auth: any CalendarAuthProviding
    let api: any CalendarAPIProviding
    let sync: SyncManager
}

@MainActor
@Observable
final class CalendarService {
    let logger = Logger(category: "CalendarService")

    // MARK: - Constants

    private static let upcomingEventsLimit = 50
    private static let startedMeetingsLimit = 20

    // MARK: - Observable State

    var isConnected = false
    var syncStatus: SyncStatus = .idle
    var events: [Event] = []
    var startedEvents: [Event] = []
    var calendars: [CalendarInfo] = []
    var lastSyncTime: Date?
    var nextSyncTime: Date?
    var userEmail: String?
    var authError: String?
    var calendarUpdateError: String?
    var connectedProviders: Set<CalendarProviderType> = []

    // MARK: - Private State

    @ObservationIgnored
    var providers: [CalendarProviderType: ProviderBackend] = [:]
    @ObservationIgnored
    private let databaseManager: any DatabaseManaging
    @ObservationIgnored
    private let preferencesManager: PreferencesManager
    @ObservationIgnored
    private let linkParser: LinkParser
    @ObservationIgnored
    var cancellables = Set<AnyCancellable>()
    // Observation stops naturally when a provider is removed from `providers`
    // (the observe* methods guard on `providers[type]` and bail if nil).

    @ObservationIgnored
    var uiRefreshTask: Task<Void, Never>?
    /// Dirty flag: set when sync or timezone changes require a UI refresh.
    /// The timer checks this alongside time-based staleness to avoid unnecessary DB reads.
    @ObservationIgnored
    var needsUIRefresh = false
    /// Debounce task for EKEventStoreChanged notifications.
    /// Apple Calendar can fire rapid bursts during iCloud sync.
    @ObservationIgnored
    var ekChangedDebounceTask: Task<Void, Never>?
    /// When true, loadCachedData() is a no-op. Set by injectSyntheticEventsForUITesting()
    /// to prevent the init-time Task from overwriting injected test data.
    @ObservationIgnored
    var usingSyntheticData = false

    /// Shared EKEventStore for Apple Calendar (reused across auth + API services)
    @ObservationIgnored
    let sharedEventStore: EKEventStore

    /// Publisher that fires after events are updated from a sync cycle.
    /// Supports multiple observers without retain-cycle risk.
    @ObservationIgnored
    private let eventsUpdatedSubject = PassthroughSubject<Void, Never>()
    var eventsUpdated: AnyPublisher<Void, Never> {
        eventsUpdatedSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    @ObservationIgnored
    let networkMonitor: NetworkMonitor?
    @ObservationIgnored
    let sleepObserver: SystemSleepObserver?

    /// Event IDs in the `events` array at last `loadCachedData()` call.
    /// Used by `hasTimeBoundaryChange()` to detect actual category transitions
    /// instead of the stale check that returned true whenever any event had started.
    @ObservationIgnored
    var lastLoadedUpcomingIDs: Set<String> = []
    /// Event IDs in the `startedEvents` array at last `loadCachedData()` call.
    @ObservationIgnored
    var lastLoadedStartedIDs: Set<String> = []

    /// Registry key for sleep/wake callbacks.
    private static let sleepKey = "CalendarService"

    init(
        preferencesManager: PreferencesManager,
        databaseManager: any DatabaseManaging,
        linkParser: LinkParser,
        networkMonitor: NetworkMonitor? = nil,
        sleepObserver: SystemSleepObserver? = nil,
        eventStore: EKEventStore = EKEventStore(),
    ) {
        self.preferencesManager = preferencesManager
        self.databaseManager = databaseManager
        self.linkParser = linkParser
        self.networkMonitor = networkMonitor
        self.sleepObserver = sleepObserver
        self.sharedEventStore = eventStore
        setupTimezoneObserver()
        setupSleepObserver()

        if AppRuntime.injectTestEvents {
            injectSyntheticEventsForUITesting()
        } else {
            startUIRefreshTimer()
            Task {
                await loadCachedData()
            }
        }
    }

    private func setupSleepObserver() {
        guard let sleepObserver else { return }
        sleepObserver.register(
            key: Self.sleepKey,
            onSleep: { [weak self] in
                self?.stopUIRefreshTimer()
            },
            onWake: { [weak self] in
                guard let self else { return }
                self.needsUIRefresh = true
                self.startUIRefreshTimer()
                Task {
                    await self.loadCachedData()
                }
            },
        )
    }

    // MARK: - Provider Management

    func connect(provider providerType: CalendarProviderType) async {
        let flow = AppDiagnostics.startFlow("connect", component: "CalendarService")
        logger.info("Connecting provider: \(providerType.rawValue)")

        let backend = getOrCreateBackend(for: providerType)

        do {
            try await backend.auth.startAuthorizationFlow()
            syncAggregatedAuthState()

            if backend.auth.isAuthenticated {
                AppDiagnostics.record(
                    component: "CalendarService",
                    phase: "connect.authenticated",
                    flowId: flow.flowId,
                ) {
                    ["provider": providerType.rawValue]
                }

                // Fetch and save calendars for this provider
                let providerCalendars = await backend.api.fetchCalendars()
                guard backend.api.lastError == nil else {
                    logger.error("Calendar fetch failed for \(providerType.rawValue)")
                    syncAggregatedAuthState()
                    AppDiagnostics.endFlow(flow, component: "CalendarService", outcome: .failure) {
                        ["provider": providerType.rawValue, "reason": "calendarFetchFailed"]
                    }
                    return
                }
                try await databaseManager.mergeCalendars(
                    provider: providerType, upstream: providerCalendars,
                )

                backend.sync.startPeriodicSync()
                await loadCachedData()

                AppDiagnostics.endFlow(flow, component: "CalendarService") {
                    [
                        "provider": providerType.rawValue,
                        "calendars": "\(providerCalendars.count)",
                    ]
                }
            } else {
                AppDiagnostics.endFlow(flow, component: "CalendarService", outcome: .skipped) {
                    ["provider": providerType.rawValue, "reason": "notAuthenticated"]
                }
            }
        } catch {
            logger.error("Connection failed for \(providerType.rawValue): \(PrivacyUtils.redactedError(error))")
            syncAggregatedAuthState()
            AppDiagnostics.endFlow(flow, component: "CalendarService", outcome: .failure) {
                ["provider": providerType.rawValue, "error": PrivacyUtils.redactedError(error)]
            }
        }
    }

    func disconnect(provider providerType: CalendarProviderType) async {
        logger.info("Disconnecting provider: \(providerType.rawValue)")

        guard let backend = providers[providerType] else { return }

        backend.sync.stopPeriodicSync()
        backend.auth.signOut()

        // Clean up provider data from database before removing provider references
        do {
            try await databaseManager.deleteAllDataForProvider(providerType)
        } catch {
            logger.error("Failed to delete data for \(providerType.rawValue): \(PrivacyUtils.redactedError(error))")
        }
        await loadCachedData()

        // Notify observers so AppState reschedules alerts without the
        // disconnected provider's events.
        eventsUpdatedSubject.send()

        // Remove bindings for this provider
        // Observation stops automatically — observe* methods guard on providers[type]
        providers[providerType] = nil

        syncAggregatedAuthState()

        // Stop UI refresh if no providers are connected
        if providers.isEmpty {
            stopUIRefreshTimer()
        }
    }

    func disconnectAll() async {
        for providerType in Array(providers.keys) {
            await disconnect(provider: providerType)
        }
    }

    // MARK: - Connection Status

    func checkConnectionStatus() async {
        guard !usingSyntheticData else { return }
        logger.debug("Checking connection status for all providers")

        // On app launch, providers dict is empty. Restore backends for
        // providers that have persisted calendars in the database.
        if providers.isEmpty {
            await restoreConnectedProviders()
        }

        for (_, backend) in providers {
            await backend.auth.validateAuthState()
        }

        syncAggregatedAuthState()

        if isConnected {
            await loadCachedData()
        }

        AppDiagnostics.record(component: "CalendarService", phase: "connectionStatus") {
            [
                "connected": "\(self.isConnected)",
                "providers": self.connectedProviders.map(\.rawValue).sorted().joined(separator: ","),
            ]
        }
    }

    /// Recreates backends for providers that have calendars in the database.
    /// Called on app launch when `providers` is empty but the database has
    /// persisted calendar rows from a previous session. Each backend's auth
    /// service restores its credentials (OAuth2Service from keychain,
    /// AppleCalendarAuthService from system permission state).
    private func restoreConnectedProviders() async {
        let providerTypes: Set<CalendarProviderType>
        do {
            let calendars = try await databaseManager.fetchCalendars()
            providerTypes = Set(calendars.map(\.sourceProvider))
        } catch {
            logger.error(
                "Failed to fetch calendars for provider restoration: \(PrivacyUtils.redactedError(error))",
            )
            return
        }

        guard !providerTypes.isEmpty else {
            logger.debug("No persisted providers to restore")
            return
        }

        for providerType in providerTypes {
            logger.info("Restoring backend for \(providerType.rawValue)")
            _ = getOrCreateBackend(for: providerType)
        }

        startUIRefreshTimer()
    }

    // MARK: - Test Injection

    /// Injects a pre-built backend for testing multi-provider aggregation.
    /// Internal access — visible to tests via @testable import but not to external consumers.
    func injectTestBackend(
        type: CalendarProviderType,
        auth: any CalendarAuthProviding,
        api: any CalendarAPIProviding,
        sync: SyncManager,
    ) {
        let backend = ProviderBackend(type: type, auth: auth, api: api, sync: sync)
        providers[type] = backend
        setupProviderBindings(for: backend)
        syncAggregatedAuthState()
    }

    /// Removes a previously injected backend and updates aggregated state.
    /// Internal access — visible to tests via @testable import.
    func removeTestBackend(type: CalendarProviderType) {
        providers[type] = nil
        syncAggregatedAuthState()
    }

    // MARK: - Sync

    /// Starts periodic sync for all authenticated providers.
    func startAllPeriodicSync() {
        for (_, backend) in providers where backend.auth.isAuthenticated {
            backend.sync.startPeriodicSync()
        }
    }

    func syncEvents() async {
        for (_, backend) in providers where backend.auth.isAuthenticated {
            await backend.sync.forceSyncNow()
        }
        await loadCachedData()
    }

    // MARK: - Calendar Selection

    func updateCalendarSelection(_ calendarId: String, isSelected: Bool) {
        if let index = calendars.firstIndex(where: { $0.id == calendarId }) {
            calendars[index] = calendars[index].withSelection(isSelected)
            calendarUpdateError = nil

            logger.debug("Updated calendar \(PrivacyUtils.redactedCalendarId(calendarId)) selection to \(isSelected)")

            let updatedCalendar = calendars[index]
            let shouldSync = isConnected
            Task {
                do {
                    try await databaseManager.saveCalendars([updatedCalendar])
                } catch {
                    calendarUpdateError = "Failed to save calendar selection: \(error.localizedDescription)"
                    logger.error("Failed to save calendar selection: \(PrivacyUtils.redactedError(error))")
                    return
                }

                if shouldSync {
                    await syncEvents()
                }
            }
        }
    }

    func updateCalendarAlertMode(_ calendarId: String, alertMode: AlertMode) {
        if let index = calendars.firstIndex(where: { $0.id == calendarId }) {
            calendars[index] = calendars[index].withAlertMode(alertMode)
            calendarUpdateError = nil

            logger
                .debug(
                    "Updated calendar \(PrivacyUtils.redactedCalendarId(calendarId)) alert mode to \(alertMode.rawValue)",
                )

            let updatedCalendar = calendars[index]
            Task {
                do {
                    try await databaseManager.saveCalendars([updatedCalendar])
                } catch {
                    calendarUpdateError = "Failed to save alert mode: \(error.localizedDescription)"
                    logger.error("Failed to save alert mode: \(PrivacyUtils.redactedError(error))")
                }
            }
        }
    }

    // MARK: - Search and Queries

    func searchEvents(query: String) async throws -> [Event] {
        try await databaseManager.searchEvents(query: query)
    }

    func getEventsForToday() async throws -> [Event] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return try await databaseManager.fetchEvents(from: today, to: tomorrow)
    }

    func getUpcomingEvents(limit: Int = 10) async throws -> [Event] {
        try await databaseManager.fetchUpcomingEvents(limit: limit)
    }

    // MARK: - Service Access

    /// Returns the SyncManager for the primary provider (Google preferred), or nil if none connected.
    /// Used by HealthMonitor and AppState — not for per-provider sync control.
    var primarySync: SyncManager? {
        providers[.google]?.sync ?? providers.values.first?.sync
    }

    // MARK: - Private Implementation

    /// Creates a fresh backend for the given provider type.
    ///
    /// **Design note:** Services (OAuth2Service, API services, SyncManager) are constructed
    /// directly rather than injected, because backends are disposable — created on connect,
    /// destroyed on disconnect. A fresh OAuth2Service after reconnect is correct behavior
    /// (the old one's auth state was cleared on disconnect). For testing, use
    /// `injectTestBackend` which bypasses this factory entirely.
    private func getOrCreateBackend(for providerType: CalendarProviderType) -> ProviderBackend {
        if let existing = providers[providerType] {
            return existing
        }

        let auth: any CalendarAuthProviding
        let api: any CalendarAPIProviding

        switch providerType {
        case .google:
            let oauthService = OAuth2Service()
            auth = oauthService
            api = GoogleCalendarAPIService(oauth2Service: oauthService, linkParser: linkParser)

        case .apple:
            let appleAuth = AppleCalendarAuthService(eventStore: sharedEventStore)
            auth = appleAuth
            api = AppleCalendarAPIService(eventStore: sharedEventStore, linkParser: linkParser)
        }

        let sync = if let networkMonitor {
            SyncManager(
                providerType: providerType,
                apiService: api,
                databaseManager: databaseManager,
                preferencesManager: preferencesManager,
                networkMonitor: networkMonitor,
                sleepObserver: sleepObserver,
            )
        } else {
            // Test path: create with a standalone NetworkMonitor
            SyncManager(
                providerType: providerType,
                apiService: api,
                databaseManager: databaseManager,
                preferencesManager: preferencesManager,
                networkMonitor: NetworkMonitor(),
                sleepObserver: sleepObserver,
            )
        }

        let backend = ProviderBackend(type: providerType, auth: auth, api: api, sync: sync)
        providers[providerType] = backend

        setupProviderBindings(for: backend)
        setupSyncCallback(for: backend)

        return backend
    }

    private func setupProviderBindings(for backend: ProviderBackend) {
        observeSyncStatus(for: backend.type)
        observeLastSyncTime(for: backend.type)
        observeNextSyncTime(for: backend.type)
    }

    private func observeSyncStatus(for providerType: CalendarProviderType) {
        guard let backend = providers[providerType] else { return }
        withObservationTracking {
            _ = backend.sync.syncStatus
        } onChange: { [weak self] in
            // onChange fires during willSet — the new value isn't stored yet.
            // Defer to the next MainActor turn so the read picks up the new value.
            Task { @MainActor [weak self] in
                guard let self, let backend = self.providers[providerType] else { return }
                self.aggregateSyncStatus(
                    changedProvider: providerType,
                    newStatus: backend.sync.syncStatus,
                )
                self.observeSyncStatus(for: providerType)
            }
        }
    }

    private func observeLastSyncTime(for providerType: CalendarProviderType) {
        guard let backend = providers[providerType] else { return }
        withObservationTracking {
            _ = backend.sync.lastSyncTime
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let backend = self.providers[providerType] else { return }
                self.aggregateSyncTimes(
                    changedProvider: providerType,
                    newLastSync: backend.sync.lastSyncTime,
                )
                self.observeLastSyncTime(for: providerType)
            }
        }
    }

    private func observeNextSyncTime(for providerType: CalendarProviderType) {
        guard let backend = providers[providerType] else { return }
        withObservationTracking {
            _ = backend.sync.nextSyncTime
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let backend = self.providers[providerType] else { return }
                self.aggregateSyncTimes(
                    changedProvider: providerType,
                    newNextSync: backend.sync.nextSyncTime,
                )
                self.observeNextSyncTime(for: providerType)
            }
        }
    }

    private func setupSyncCallback(for backend: ProviderBackend) {
        backend.sync.onSyncCompleted = { [weak self, providerType = backend.type] in
            await self?.loadCachedData()
            self?.needsUIRefresh = true
            self?.eventsUpdatedSubject.send()
            self?.logger.debug("UI refreshed after \(providerType.rawValue) sync")
            AppDiagnostics.record(component: "CalendarService", phase: "syncCallback") {
                [
                    "provider": providerType.rawValue,
                    "events": "\(self?.events.count ?? 0)",
                    "started": "\(self?.startedEvents.count ?? 0)",
                ]
            }
        }
    }

    private func setupTimezoneObserver() {
        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.needsUIRefresh = true
                    await self?.loadCachedData()
                }
            }
            .store(in: &cancellables)

        setupEventStoreChangeObserver()
    }

    // MARK: - Aggregated State

    private func syncAggregatedAuthState() {
        let authenticatedProviders = providers.values.filter(\.auth.isAuthenticated)
        connectedProviders = Set(authenticatedProviders.map(\.type))
        isConnected = !authenticatedProviders.isEmpty

        // Show email from Google if available, otherwise nil
        userEmail = providers[.google]?.auth.userEmail

        // Show first auth error if any
        authError = providers.values.compactMap(\.auth.authorizationError).first
    }

    /// Aggregates sync status using `newStatus` for the provider that just changed
    /// and reading other providers' current values (which are stable during willSet).
    private func aggregateSyncStatus(
        changedProvider: CalendarProviderType, newStatus: SyncStatus,
    ) {
        var statuses: [SyncStatus] = []
        for (type, backend) in providers {
            statuses.append(type == changedProvider ? newStatus : backend.sync.syncStatus)
        }

        if statuses.contains(where: \.isSyncing) {
            syncStatus = .syncing
        } else if let errorStatus = statuses.first(where: \.isError) {
            syncStatus = errorStatus
        } else if statuses.contains(where: { $0 == .offline }) {
            syncStatus = .offline
        } else {
            syncStatus = .idle
        }
    }

    /// Aggregates sync times, substituting the delivered value for the provider that changed.
    private func aggregateSyncTimes(
        changedProvider: CalendarProviderType,
        newLastSync: Date? = nil,
        newNextSync: Date? = nil,
    ) {
        var lastSyncTimes: [Date] = []
        var nextSyncTimes: [Date] = []

        for (type, backend) in providers {
            if type == changedProvider {
                if let t = newLastSync ?? backend.sync.lastSyncTime { lastSyncTimes.append(t) }
                if let t = newNextSync ?? backend.sync.nextSyncTime { nextSyncTimes.append(t) }
            } else {
                if let t = backend.sync.lastSyncTime { lastSyncTimes.append(t) }
                if let t = backend.sync.nextSyncTime { nextSyncTimes.append(t) }
            }
        }

        lastSyncTime = lastSyncTimes.max()
        nextSyncTime = nextSyncTimes.min()
    }

    @discardableResult
    func loadCachedData() async -> Bool {
        guard !usingSyntheticData else { return true }
        do {
            let newCalendars = try await databaseManager.fetchCalendars()
            let newEvents = try await Self.deduplicateEvents(
                databaseManager.fetchUpcomingEvents(limit: Self.upcomingEventsLimit),
            )
            let newStarted = try await Self.deduplicateEvents(
                databaseManager.fetchStartedMeetings(limit: Self.startedMeetingsLimit),
            )

            // Only mutate Observable properties when data actually changed.
            // Skipping no-op writes prevents observation callbacks from firing
            // every 5–60s when the UI refresh timer runs between syncs.
            if calendars != newCalendars { calendars = newCalendars }
            if events != newEvents { events = newEvents }
            if startedEvents != newStarted { startedEvents = newStarted }

            // Update boundary tracking for hasTimeBoundaryChange()
            lastLoadedUpcomingIDs = Set(newEvents.map(\.id))
            lastLoadedStartedIDs = Set(newStarted.map(\.id))

            logger.debug(
                "Cache loaded: \(newCalendars.count) calendars, \(newEvents.count) upcoming, \(newStarted.count) started",
            )
            AppDiagnostics.record(component: "CalendarService", phase: "cacheLoaded") {
                [
                    "calendars": "\(newCalendars.count)",
                    "upcoming": "\(newEvents.count)",
                    "started": "\(newStarted.count)",
                ]
            }
            return true
        } catch {
            logger.error("Failed to load cached data: \(PrivacyUtils.redactedError(error))")
            AppDiagnostics.record(
                component: "CalendarService",
                phase: "cacheLoaded",
                outcome: .failure,
            ) {
                ["error": PrivacyUtils.redactedError(error)]
            }
            return false
        }
    }
}
