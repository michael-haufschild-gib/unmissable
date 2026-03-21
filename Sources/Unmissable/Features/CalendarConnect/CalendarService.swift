import Combine
import EventKit
import Foundation
import OSLog

/// Internal representation of a connected calendar provider backend.
private struct ProviderBackend {
    let type: CalendarProviderType
    let auth: any CalendarAuthProviding
    let api: any CalendarAPIProviding
    let sync: SyncManager
}

@MainActor
final class CalendarService: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "CalendarService")

    // MARK: - Published State

    @Published
    var isConnected = false
    @Published
    var syncStatus: SyncStatus = .idle
    @Published
    var events: [Event] = []
    @Published
    var startedEvents: [Event] = []
    @Published
    var calendars: [CalendarInfo] = []
    @Published
    var lastSyncTime: Date?
    @Published
    var nextSyncTime: Date?
    @Published
    var userEmail: String?
    @Published
    var authError: String?
    @Published
    var calendarUpdateError: String?
    @Published
    var connectedProviders: Set<CalendarProviderType> = []

    // MARK: - Private State

    private var providers: [CalendarProviderType: ProviderBackend] = [:]
    private let databaseManager: any DatabaseManaging
    private let preferencesManager: PreferencesManager
    private var cancellables = Set<AnyCancellable>()
    private var providerCancellables: [CalendarProviderType: Set<AnyCancellable>] = [:]
    private var uiRefreshTask: Task<Void, Never>?
    /// Dirty flag: set when sync or timezone changes require a UI refresh.
    /// The timer checks this alongside time-based staleness to avoid unnecessary DB reads.
    private var needsUIRefresh = false

    /// Shared EKEventStore for Apple Calendar (reused across auth + API services)
    private let sharedEventStore: EKEventStore

    /// Publisher that fires after events are updated from a sync cycle.
    /// Supports multiple observers without retain-cycle risk.
    private let eventsUpdatedSubject = PassthroughSubject<Void, Never>()
    var eventsUpdated: AnyPublisher<Void, Never> {
        eventsUpdatedSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(
        preferencesManager: PreferencesManager,
        databaseManager: any DatabaseManaging,
        eventStore: EKEventStore = EKEventStore()
    ) {
        self.preferencesManager = preferencesManager
        self.databaseManager = databaseManager
        self.sharedEventStore = eventStore
        setupTimezoneObserver()
        startUIRefreshTimer()
        Task {
            await loadCachedData()
        }
    }

    // MARK: - Provider Management

    func connect(provider providerType: CalendarProviderType) async {
        logger.info("Connecting provider: \(providerType.rawValue)")

        let backend = getOrCreateBackend(for: providerType)

        do {
            try await backend.auth.startAuthorizationFlow()
            syncAggregatedAuthState()

            if backend.auth.isAuthenticated {
                // Fetch and save calendars for this provider
                let providerCalendars = await backend.api.fetchCalendars()
                guard backend.api.lastError == nil else {
                    logger.error("Calendar fetch failed for \(providerType.rawValue)")
                    syncAggregatedAuthState()
                    return
                }
                try await databaseManager.saveCalendars(providerCalendars)

                backend.sync.startPeriodicSync()
                await loadCachedData()
            }
        } catch {
            logger.error("Connection failed for \(providerType.rawValue): \(error.localizedDescription)")
            syncAggregatedAuthState()
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
            logger.error("Failed to delete data for \(providerType.rawValue): \(error.localizedDescription)")
        }
        await loadCachedData()

        // Remove bindings for this provider
        providerCancellables[providerType] = nil
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
        logger.debug("Checking connection status for all providers")

        for (_, backend) in providers {
            await backend.auth.validateAuthState()
        }

        syncAggregatedAuthState()

        if isConnected {
            await loadCachedData()
        }
    }

    // MARK: - Sync

    func syncEvents() async {
        for (_, backend) in providers where backend.auth.isAuthenticated {
            await backend.sync.performSync()
        }
        await loadCachedData()
    }

    // MARK: - Calendar Selection

    func updateCalendarSelection(_ calendarId: String, isSelected: Bool) {
        if let index = calendars.firstIndex(where: { $0.id == calendarId }) {
            calendars[index] = calendars[index].withSelection(isSelected)
            calendarUpdateError = nil

            logger.debug("Updated calendar \(calendarId) selection to \(isSelected)")

            let updatedCalendar = calendars[index]
            Task {
                do {
                    try await databaseManager.saveCalendars([updatedCalendar])
                } catch {
                    calendarUpdateError = "Failed to save calendar selection: \(error.localizedDescription)"
                    logger.error("Failed to save calendar selection: \(error.localizedDescription)")
                }
            }

            if isConnected {
                Task {
                    await syncEvents()
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

    /// Returns the SyncManager for the first available provider, or nil if none connected.
    var sync: SyncManager? {
        providers[.google]?.sync ?? providers.values.first?.sync
    }

    // MARK: - Private Implementation

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
            api = GoogleCalendarAPIService(oauth2Service: oauthService)

        case .apple:
            let appleAuth = AppleCalendarAuthService(eventStore: sharedEventStore)
            auth = appleAuth
            api = AppleCalendarAPIService(eventStore: sharedEventStore)
        }

        let sync = SyncManager(
            apiService: api, databaseManager: databaseManager,
            preferencesManager: preferencesManager
        )

        let backend = ProviderBackend(type: providerType, auth: auth, api: api, sync: sync)
        providers[providerType] = backend

        setupProviderBindings(for: backend)
        setupSyncCallback(for: backend)

        return backend
    }

    private func setupProviderBindings(for backend: ProviderBackend) {
        var subs = Set<AnyCancellable>()

        // When any provider's sync status changes, update aggregated status
        backend.sync.$syncStatus
            .sink { [weak self] _ in
                self?.syncAggregatedSyncStatus()
            }
            .store(in: &subs)

        backend.sync.$lastSyncTime
            .sink { [weak self] _ in
                self?.syncAggregatedSyncTimes()
            }
            .store(in: &subs)

        backend.sync.$nextSyncTime
            .sink { [weak self] _ in
                self?.syncAggregatedSyncTimes()
            }
            .store(in: &subs)

        providerCancellables[backend.type] = subs
    }

    private func setupSyncCallback(for backend: ProviderBackend) {
        backend.sync.onSyncCompleted = { [weak self] in
            await self?.loadCachedData()
            self?.needsUIRefresh = true
            self?.eventsUpdatedSubject.send()
            self?.logger.debug("UI refreshed after \(backend.type.rawValue) sync")
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

    private func syncAggregatedSyncStatus() {
        let statuses = providers.values.map(\.sync.syncStatus)

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

    private func syncAggregatedSyncTimes() {
        // Most recent sync time across all providers
        lastSyncTime = providers.values.compactMap(\.sync.lastSyncTime).max()
        // Earliest next sync time
        nextSyncTime = providers.values.compactMap(\.sync.nextSyncTime).min()
    }

    private func loadCachedData() async {
        do {
            calendars = try await databaseManager.fetchCalendars()
            events = try await databaseManager.fetchUpcomingEvents(limit: 50)
            startedEvents = try await databaseManager.fetchStartedMeetings(limit: 20)

            logger.debug(
                "Cache loaded: \(self.calendars.count) calendars, \(self.events.count) upcoming, \(self.startedEvents.count) started"
            )
        } catch {
            logger.error("Failed to load cached data: \(error.localizedDescription)")
        }
    }

    // MARK: - UI Refresh Timer

    /// Whether any event crossed a time boundary (started or ended) since the arrays were last loaded.
    private func hasTimeBoundaryChange() -> Bool {
        let now = Date()
        // An upcoming event has started since last refresh
        if events.contains(where: { $0.startDate <= now }) {
            return true
        }
        // A started event has ended since last refresh
        if startedEvents.contains(where: { $0.endDate <= now }) {
            return true
        }
        return false
    }

    private func startUIRefreshTimer() {
        uiRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                    if !Task.isCancelled, needsUIRefresh || hasTimeBoundaryChange() {
                        needsUIRefresh = false
                        await loadCachedData()
                    }
                } catch {
                    break
                }
            }
        }
        logger.debug("UI refresh timer started")
    }

    private func stopUIRefreshTimer() {
        uiRefreshTask?.cancel()
        uiRefreshTask = nil
        logger.debug("UI refresh timer stopped")
    }
}
