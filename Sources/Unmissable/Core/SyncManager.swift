import Combine
import Foundation
import Network
import OSLog

@MainActor
final class SyncManager: ObservableObject {
    private let logger = Logger(category: "SyncManager")

    @Published
    var syncStatus: SyncStatus = .idle
    @Published
    var lastSyncTime: Date?
    @Published
    var nextSyncTime: Date?
    @Published
    var isOnline: Bool = true
    @Published
    var retryCount: Int = 0

    private let apiService: any CalendarAPIProviding
    private let databaseManager: any DatabaseManaging
    private let preferencesManager: PreferencesManager
    private var syncTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?
    private var networkMonitorTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // Sync completion callback
    var onSyncCompleted: (() async -> Void)?
    private let eventLookAheadDays = 7 // Sync events for next 7 days

    // Retry configuration
    private let maxRetries = 5
    private let baseRetryDelay: TimeInterval = 5.0 // Start with 5 seconds
    private var retryTask: Task<Void, Never>?

    // Rate limiting configuration
    private var lastManualSyncTime: Date?
    private let minSyncCooldown: TimeInterval = 10.0 // Minimum 10 seconds between manual syncs

    // Network monitor debouncing
    private var pendingNetworkUpdate: Task<Void, Never>?
    private let networkDebounceDelay: TimeInterval = 0.5 // 500ms debounce

    // Staleness TTL: clear cached events when the API consistently returns empty
    private var lastSuccessfulNonEmptySync: Date?
    private let stalenessTTL: TimeInterval = 2 * 60 * 60 // 2 hours

    init(
        apiService: any CalendarAPIProviding, databaseManager: any DatabaseManaging,
        preferencesManager: PreferencesManager
    ) {
        self.apiService = apiService
        self.databaseManager = databaseManager
        self.preferencesManager = preferencesManager
        setupNetworkMonitoring()
        setupPreferencesObserver()
    }

    deinit {
        // Cancel async tasks first (they may reference the monitor)
        networkMonitorTask?.cancel()
        pendingNetworkUpdate?.cancel()
        syncTask?.cancel()
        retryTask?.cancel()
        // Then cancel the monitor itself
        networkMonitor?.cancel()
    }

    private var syncInterval: TimeInterval {
        TimeInterval(preferencesManager.syncIntervalSeconds)
    }

    private func setupPreferencesObserver() {
        // Watch for sync interval changes
        preferencesManager.$syncIntervalSeconds
            .sink { [weak self] _ in
                Task { @MainActor in
                    // Restart periodic sync with new interval
                    if self?.syncTask != nil {
                        self?.stopPeriodicSync()
                        self?.startPeriodicSync()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func setupNetworkMonitoring() {
        let monitor = NWPathMonitor()
        networkMonitor = monitor

        // Create async stream for network path updates
        let pathStream = AsyncStream<NWPath> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path)
            }
            continuation.onTermination = { _ in
                monitor.cancel()
            }
        }

        // Start monitor on a background queue (required by NWPathMonitor)
        monitor.start(queue: DispatchQueue(label: "com.unmissable.network", qos: .utility))

        // Process path updates asynchronously
        networkMonitorTask = Task { @MainActor [weak self] in
            for await path in pathStream {
                guard !Task.isCancelled else { break }
                self?.handleNetworkPathUpdate(path)
            }
        }
    }

    private func handleNetworkPathUpdate(_ path: NWPath) {
        // Debounce rapid network status changes
        pendingNetworkUpdate?.cancel()

        pendingNetworkUpdate = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(networkDebounceDelay * 1000))
            } catch is CancellationError {
                return // Debounced - a newer update superseded this one
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let wasOnline = isOnline
            isOnline = path.status == .satisfied

            if !wasOnline, isOnline {
                logger.info("Network connection restored, attempting sync")
                await performSync()
            } else if !isOnline {
                logger.warning("Network connection lost")
                syncStatus = .offline
            }
        }
    }

    func startPeriodicSync() {
        guard syncTask == nil else {
            logger.debug("Periodic sync already running")
            return
        }

        let intervalSeconds = syncInterval
        logger.info("Starting periodic sync every \(Int(intervalSeconds))s")

        // Schedule periodic sync
        syncTask = Task { @MainActor in
            // First sync immediately
            await performSync()

            // Then repeat every interval
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(intervalSeconds))
                    if !Task.isCancelled {
                        await performSync()
                    }
                } catch {
                    // Task was cancelled, exit the loop
                    break
                }
            }
        }

        updateNextSyncTime()
    }

    func stopPeriodicSync() {
        syncTask?.cancel()
        syncTask = nil
        nextSyncTime = nil
        resetRetryCount()
        logger.info("Stopped periodic sync")
    }

    func performSync(isManualSync: Bool = false) async {
        guard shouldStartSync(isManualSync: isManualSync) else { return }

        syncStatus = .syncing
        logger.debug("Starting calendar sync (attempt \(self.retryCount + 1))")

        let selectedCalendarIds: [String]
        do {
            let calendars = try await databaseManager.fetchCalendars()
            selectedCalendarIds = calendars.filter(\.isSelected).map(\.id)
        } catch {
            logger.error("Database read error fetching calendars: \(error.localizedDescription)")
            syncStatus = .error("Database read error: \(error.localizedDescription)")
            return
        }

        guard !selectedCalendarIds.isEmpty else {
            logger.warning("No calendars selected for sync")
            completeSync()
            return
        }

        do {
            let fetchedEvents = try await fetchEventsFromAPI(for: selectedCalendarIds)

            if fetchedEvents.isEmpty {
                await handleEmptyFetchResult(for: selectedCalendarIds)
                return
            }

            await saveAndFinalize(
                fetchedEvents: fetchedEvents,
                selectedCalendarIds: selectedCalendarIds
            )
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            handleSyncError(error)
        }
    }

    /// Checks preconditions for starting a sync: rate limits, online status, and
    /// whether a sync is already in progress.
    private func shouldStartSync(isManualSync: Bool) -> Bool {
        if isManualSync {
            if let lastSync = lastManualSyncTime,
               Date().timeIntervalSince(lastSync) < minSyncCooldown
            {
                let remaining = Int(minSyncCooldown - Date().timeIntervalSince(lastSync))
                logger.debug("Manual sync rate limited - \(remaining)s remaining")
                return false
            }
            lastManualSyncTime = Date()
        }

        guard isOnline else {
            logger.debug("Skipping sync - device is offline")
            syncStatus = .offline
            return false
        }

        guard syncStatus != .syncing else {
            logger.debug("Sync already in progress, skipping")
            return false
        }

        return true
    }

    /// Fetches events from the API for the given calendar IDs over the configured look-ahead window.
    private func fetchEventsFromAPI(for calendarIds: [String]) async throws -> [Event] {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endDate = Calendar.current.date(
            byAdding: .day, value: eventLookAheadDays, to: now
        ) ?? now

        let fetchedEvents = await apiService.fetchEvents(
            for: calendarIds,
            from: startOfDay,
            to: endDate
        )

        if fetchedEvents.isEmpty, let apiError = apiService.lastError {
            throw SyncError.apiFetchFailed(apiError)
        }

        if let partialError = apiService.lastError {
            logger.warning("Partial sync failure (some calendars unavailable): \(partialError)")
        }

        return fetchedEvents
    }

    /// Handles the case where the API returns zero events with no error.
    /// Uses a staleness TTL to decide whether to clear cached events or preserve them.
    private func handleEmptyFetchResult(for calendarIds: [String]) async {
        if lastSuccessfulNonEmptySync == nil {
            // First empty result (e.g. after app restart) — start the staleness clock
            // so the TTL can trigger on subsequent empty fetches.
            lastSuccessfulNonEmptySync = Date()
        }

        if let lastNonEmpty = lastSuccessfulNonEmptySync,
           Date().timeIntervalSince(lastNonEmpty) > stalenessTTL
        {
            logger.info(
                "API returned zero events for >\(Int(self.stalenessTTL / 3600))h — clearing stale cache"
            )
            for calendarId in calendarIds {
                do {
                    try await databaseManager.replaceEvents(for: calendarId, with: [])
                } catch {
                    logger.error(
                        "Failed to clear events for calendar \(calendarId): \(error.localizedDescription)"
                    )
                }
            }
        } else {
            logger.info(
                "API returned zero events for \(calendarIds.count) calendars — preserving cache"
            )
        }
        completeSync()
        await onSyncCompleted?()
    }

    /// Saves fetched events per calendar and finalizes the sync cycle.
    private func saveAndFinalize(
        fetchedEvents: [Event],
        selectedCalendarIds: [String]
    ) async {
        let eventsByCalendar = Dictionary(grouping: fetchedEvents) { $0.calendarId }

        let failedCount = await saveEventsPerCalendar(
            eventsByCalendar: eventsByCalendar,
            selectedCalendarIds: selectedCalendarIds
        )

        if failedCount == selectedCalendarIds.count {
            syncStatus = .error("Database write error: failed to save events for all calendars")
            return
        }

        lastSuccessfulNonEmptySync = Date()
        completeSync()

        logger.info(
            "Sync completed: \(fetchedEvents.count) events from \(selectedCalendarIds.count) calendars"
        )
        await onSyncCompleted?()
    }

    /// Resets sync state to idle after a successful sync cycle.
    private func completeSync() {
        syncStatus = .idle
        updateSyncTimes()
        resetRetryCount()
    }

    /// Routes a sync error to the appropriate handler (network vs. other).
    private func handleSyncError(_ error: Error) {
        if isNetworkError(error) {
            handleNetworkError(error)
        } else {
            syncStatus = .error(error.localizedDescription)
            resetRetryCount()
        }
        updateNextSyncTime()
    }

    private func saveEventsPerCalendar(
        eventsByCalendar: [String: [Event]],
        selectedCalendarIds: [String]
    ) async -> Int {
        logger.debug("Saving events to database (transactional per calendar)")
        var failedCalendars: [String] = []
        for calendarId in selectedCalendarIds {
            guard let calendarEvents = eventsByCalendar[calendarId] else {
                // No events returned for this calendar — either a fetch failure or
                // genuinely empty. Preserve cached events to avoid deleting valid data
                // on partial API failures. Genuinely empty calendars are handled by
                // the staleness TTL in handleEmptyFetchResult.
                logger.debug("No API data for calendar \(calendarId), preserving cache")
                continue
            }
            do {
                try await databaseManager.replaceEvents(for: calendarId, with: calendarEvents)
                try await databaseManager.updateCalendarSyncTime(calendarId)
            } catch {
                failedCalendars.append(calendarId)
                logger.error(
                    "Failed to save events for calendar \(calendarId): \(error.localizedDescription)"
                )
            }
        }
        if !failedCalendars.isEmpty {
            logger.warning(
                "Partial sync: \(failedCalendars.count)/\(selectedCalendarIds.count) calendars failed to save"
            )
        }
        return failedCalendars.count
    }

    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        // Only classify transient connectivity failures as network errors.
        // Non-network URL errors (bad URL, auth required, bad server response)
        // should not be retried with backoff — they won't self-resolve.
        let transientNetworkCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed,
        ]
        return transientNetworkCodes.contains(nsError.code)
    }

    private func handleNetworkError(_ error: Error) {
        logger.warning("Network error encountered: \(error.localizedDescription)")
        guard retryCount < maxRetries else {
            logger.error("Max retries reached, giving up")
            syncStatus = .error("Network error after \(maxRetries) attempts")
            resetRetryCount()
            return
        }

        retryCount += 1
        let retryDelay = calculateRetryDelay()

        logger.info(
            "Network error occurred, retrying in \(retryDelay) seconds (attempt \(self.retryCount)/\(self.maxRetries))"
        )
        syncStatus = .error("Retrying in \(Int(retryDelay))s...")

        retryTask?.cancel()
        retryTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(retryDelay))
                if !Task.isCancelled {
                    await performSync()
                }
            } catch is CancellationError {
                // Expected cancellation, do nothing
                logger.debug("Retry task cancelled")
            } catch {
                logger.error("Unexpected retry task error: \(error.localizedDescription)")
            }
        }
    }

    private func calculateRetryDelay() -> TimeInterval {
        // Exponential backoff with jitter
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(retryCount - 1))
        let jitter = Double.random(in: 0.8 ... 1.2) // ±20% jitter
        return min(exponentialDelay * jitter, 300.0) // Cap at 5 minutes
    }

    private func resetRetryCount() {
        retryCount = 0
        retryTask?.cancel()
        retryTask = nil
    }

    private func updateSyncTimes() {
        lastSyncTime = Date()
        updateNextSyncTime()
    }

    private func updateNextSyncTime() {
        if syncTask != nil {
            nextSyncTime = Date().addingTimeInterval(syncInterval)
        } else {
            nextSyncTime = nil
        }
    }

    // MARK: - Manual Operations

    func forceSyncNow() async {
        logger.debug("Force sync requested")
        await performSync(isManualSync: true)
    }

    // MARK: - Database Operations

    func getUpcomingEvents(limit: Int = 10) async throws -> [Event] {
        try await databaseManager.fetchUpcomingEvents(limit: limit)
    }

    func getEventsInRange(from startDate: Date, to endDate: Date) async throws -> [Event] {
        try await databaseManager.fetchEvents(from: startDate, to: endDate)
    }

    func searchEvents(query: String) async throws -> [Event] {
        try await databaseManager.searchEvents(query: query)
    }

    func performDatabaseMaintenance() async {
        logger.debug("Performing database maintenance")
        do {
            try await databaseManager.performMaintenance()
        } catch {
            logger.error("Database maintenance failed: \(error.localizedDescription)")
        }
    }
}

enum SyncError: LocalizedError {
    case apiFetchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .apiFetchFailed(reason):
            "Calendar sync failed: \(reason)"
        }
    }
}
