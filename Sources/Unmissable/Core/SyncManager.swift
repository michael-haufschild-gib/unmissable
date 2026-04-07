import Foundation
import Network
import Observation
import OSLog

@MainActor
@Observable
final class SyncManager {
    let logger = Logger(category: "SyncManager")

    var syncStatus: SyncStatus = .idle
    var lastSyncTime: Date?
    var nextSyncTime: Date?
    var isOnline: Bool = true
    var retryCount: Int = 0

    @ObservationIgnored
    let providerType: CalendarProviderType
    @ObservationIgnored
    private let apiService: any CalendarAPIProviding
    @ObservationIgnored
    private let databaseManager: any DatabaseManaging
    @ObservationIgnored
    private let preferencesManager: PreferencesManager
    @ObservationIgnored
    private var syncTask: Task<Void, Never>?
    @ObservationIgnored
    private var networkMonitor: NWPathMonitor?
    @ObservationIgnored
    private var networkMonitorTask: Task<Void, Never>?

    /// Sync completion callback
    @ObservationIgnored
    var onSyncCompleted: (() async -> Void)?
    @ObservationIgnored
    private let eventLookAheadDays = 7 // Sync events for next 7 days

    /// Retry configuration
    @ObservationIgnored
    private let maxRetries = 5
    @ObservationIgnored
    private let baseRetryDelay: TimeInterval = 5.0 // Start with 5 seconds
    @ObservationIgnored
    private var retryTask: Task<Void, Never>?

    /// Rate limiting configuration
    @ObservationIgnored
    private var lastManualSyncTime: Date?
    @ObservationIgnored
    private let minSyncCooldown: TimeInterval = 10.0 // Minimum 10 seconds between manual syncs

    /// Network monitor debouncing
    @ObservationIgnored
    private var pendingNetworkUpdate: Task<Void, Never>?
    @ObservationIgnored
    private let networkDebounceDelay: TimeInterval = 0.5 // 500ms debounce

    /// Staleness TTL: clear cached events when the API consistently returns empty
    @ObservationIgnored
    private var stalenessReferenceDate: Date?
    /// Staleness TTL: 2 hours in seconds.
    private static let stalenessHours = 2
    /// Seconds per hour, used for staleness TTL computation.
    private static let secondsPerHour: TimeInterval = 3600
    private let stalenessTTL = TimeInterval(stalenessHours) * secondsPerHour

    /// Milliseconds per second, used for network debounce conversion.
    private static let millisecondsPerSecond: Double = 1000
    /// Maximum retry delay cap (seconds) — 5 minutes.
    private static let maxRetryDelaySeconds: TimeInterval = 300.0
    /// Exponential backoff base multiplier.
    private static let backoffBase: Double = 2.0
    /// Jitter range lower bound for retry delay randomization.
    private static let jitterLowerBound: Double = 0.8
    /// Jitter range upper bound for retry delay randomization.
    private static let jitterUpperBound: Double = 1.2

    init(
        providerType: CalendarProviderType,
        apiService: any CalendarAPIProviding,
        databaseManager: any DatabaseManaging,
        preferencesManager: PreferencesManager,
    ) {
        self.providerType = providerType
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

    var syncInterval: TimeInterval {
        TimeInterval(preferencesManager.syncIntervalSeconds)
    }

    private func setupPreferencesObserver() {
        observeSyncInterval()
    }

    private func observeSyncInterval() {
        withObservationTracking {
            _ = preferencesManager.syncIntervalSeconds
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Restart periodic sync with new interval
                if self.syncTask != nil {
                    self.stopPeriodicSync()
                    self.startPeriodicSync()
                }
                self.observeSyncInterval()
            }
        }
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
                try await Task.sleep(
                    for: .milliseconds(networkDebounceDelay * Self.millisecondsPerSecond),
                )
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

        logger.info("Starting periodic sync (base interval: \(Int(self.syncInterval))s)")

        // Schedule periodic sync
        syncTask = Task { @MainActor in
            // First sync immediately
            await performSync()

            // Then repeat — interval adapts to time of day each cycle
            while !Task.isCancelled {
                do {
                    let interval = effectiveSyncInterval()
                    try await Task.sleep(for: .seconds(interval))
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

        let flow = AppDiagnostics.startFlow("sync", component: "SyncManager")
        syncStatus = .syncing
        logger.debug("Starting calendar sync (attempt \(self.retryCount + 1))")

        let selectedCalendarIds: [String]
        do {
            let calendars = try await databaseManager.fetchCalendars(for: providerType)
            selectedCalendarIds = calendars.filter(\.isSelected).map(\.id)
        } catch {
            logger.error("Database read error fetching calendars: \(PrivacyUtils.redactedError(error))")
            syncStatus = .error("Database read error: \(error.localizedDescription)")
            AppDiagnostics.endFlow(flow, component: "SyncManager", outcome: .failure) {
                ["reason": "dbReadError", "error": PrivacyUtils.redactedError(error)]
            }
            return
        }

        guard !selectedCalendarIds.isEmpty else {
            logger.warning("No calendars selected for sync")
            syncStatus = .idle
            updateNextSyncTime()
            AppDiagnostics.endFlow(flow, component: "SyncManager", outcome: .skipped) {
                ["reason": "noCalendarsSelected"]
            }
            return
        }

        await executeSyncCycle(
            calendarIds: selectedCalendarIds,
            flow: flow,
            isManualSync: isManualSync,
        )
    }

    /// Fetches events for the given calendars, logs diagnostics, and saves results.
    private func executeSyncCycle(
        calendarIds: [String],
        flow: FlowContext,
        isManualSync: Bool,
    ) async {
        AppDiagnostics.record(
            component: "SyncManager",
            phase: "sync.preconditions",
            flowId: flow.flowId,
        ) {
            [
                "provider": self.providerType.rawValue,
                "selectedCalendars": "\(calendarIds.count)",
                "attempt": "\(self.retryCount + 1)",
                "isManual": "\(isManualSync)",
            ]
        }

        do {
            let results = await fetchEventsFromAPI(for: calendarIds)
            var totalEventCount = 0
            var failCount = 0
            for result in results.values {
                switch result {
                case let .success(events): totalEventCount += events.count
                case .failure: failCount += 1
                }
            }
            let allSucceeded = failCount == 0
            let allFailed = failCount == results.count

            AppDiagnostics.record(
                component: "SyncManager",
                phase: "sync.fetchResults",
                flowId: flow.flowId,
            ) {
                var meta: [String: String] = [
                    "totalEvents": "\(totalEventCount)",
                    "allSucceeded": "\(allSucceeded)",
                    "allFailed": "\(allFailed)",
                ]
                for (calId, result) in results {
                    let key = PrivacyUtils.redactedCalendarId(calId)
                    switch result {
                    case let .success(events):
                        meta["cal:\(key)"] = "ok(\(events.count))"
                    case let .failure(error):
                        meta["cal:\(key)"] = "fail(\(PrivacyUtils.redactedError(error)))"
                    }
                }
                return meta
            }

            if allFailed {
                let errors = results.values.compactMap { result -> String? in
                    if case let .failure(error) = result { return error.localizedDescription }
                    return nil
                }
                throw SyncError.apiFetchFailed(errors.first ?? "Unknown error")
            }

            if totalEventCount == 0, allSucceeded {
                await handleAllEmptySuccess(for: calendarIds)
                AppDiagnostics.endFlow(flow, component: "SyncManager") {
                    ["outcome": "allEmpty", "calendars": "\(calendarIds.count)"]
                }
                return
            }

            await saveAndFinalize(results: results, selectedCalendarIds: calendarIds)
            AppDiagnostics.endFlow(flow, component: "SyncManager") {
                ["events": "\(totalEventCount)", "calendars": "\(calendarIds.count)"]
            }
        } catch {
            logger.error("Sync failed: \(PrivacyUtils.redactedError(error))")
            handleSyncError(error)
            AppDiagnostics.endFlow(flow, component: "SyncManager", outcome: .failure) {
                ["error": PrivacyUtils.redactedError(error)]
            }
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
    /// Returns per-calendar results so callers can distinguish "confirmed empty" from "failed to fetch."
    private func fetchEventsFromAPI(for calendarIds: [String]) async -> CalendarFetchResults {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endDate = Calendar.current.date(
            byAdding: .day, value: eventLookAheadDays, to: now,
        ) ?? now

        let results = await apiService.fetchEvents(
            for: calendarIds,
            from: startOfDay,
            to: endDate,
        )

        let failedCount = results.values.count(where: { if case .failure = $0 { return true }
            return false
        })
        if failedCount > 0 {
            logger.warning(
                "Partial sync failure: \(failedCount)/\(calendarIds.count) calendars unavailable",
            )
        }

        return results
    }

    /// Handles the case where ALL calendars returned `.success([])` — every calendar
    /// confirmed zero events. Uses a staleness TTL to decide whether to clear cached events,
    /// as defense-in-depth against API bugs that return 200 with empty results.
    private func handleAllEmptySuccess(for calendarIds: [String]) async {
        if stalenessReferenceDate == nil {
            // First all-empty result (e.g. after app restart) — start the staleness clock
            // so the TTL can trigger on subsequent empty fetches.
            stalenessReferenceDate = Date()
        }

        if let referenceDate = stalenessReferenceDate,
           Date().timeIntervalSince(referenceDate) > stalenessTTL
        {
            let staleTTLHours = Int(stalenessTTL / Self.secondsPerHour)
            logger.info(
                "All calendars confirmed empty for >\(staleTTLHours)h — clearing stale cache",
            )
            for calendarId in calendarIds {
                do {
                    try await databaseManager.replaceEvents(for: calendarId, with: [])
                } catch {
                    logger.error(
                        "Failed to clear events for calendar \(PrivacyUtils.redactedCalendarId(calendarId)): \(error.localizedDescription)",
                    )
                }
            }
        } else {
            logger.info(
                "All \(calendarIds.count) calendars confirmed empty — preserving cache (staleness TTL)",
            )
        }
        completeSync()
        await onSyncCompleted?()
    }

    /// Saves fetched events per calendar and finalizes the sync cycle.
    private func saveAndFinalize(
        results: CalendarFetchResults,
        selectedCalendarIds: [String],
    ) async {
        let dbFailedCount = await saveEventsPerCalendar(
            results: results,
            selectedCalendarIds: selectedCalendarIds,
        )

        if dbFailedCount == selectedCalendarIds.count {
            syncStatus = .error("Database write error: failed to save events for all calendars")
            return
        }

        let totalEventCount = results.values.reduce(0) { count, result in
            if case let .success(events) = result { return count + events.count }
            return count
        }
        stalenessReferenceDate = Date()
        completeSync()

        logger.info(
            "Sync completed: \(totalEventCount) events from \(selectedCalendarIds.count) calendars",
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

    /// Saves per-calendar results to the database. For each calendar:
    /// - `.success(events)` -> replace cached events (even if empty — the API confirmed the state)
    /// - `.failure` -> preserve cached events (we don't know the calendar's true state)
    /// Returns the number of calendars that failed to save to the database.
    private func saveEventsPerCalendar(
        results: CalendarFetchResults,
        selectedCalendarIds: [String],
    ) async -> Int {
        logger.debug("Saving events to database (transactional per calendar)")
        var dbFailedCalendars: [String] = []
        for calendarId in selectedCalendarIds {
            guard let result = results[calendarId] else {
                // Calendar ID not in results — should not happen if implementations
                // follow the contract. Preserve cache defensively.
                logger
                    .warning(
                        "Calendar \(PrivacyUtils.redactedCalendarId(calendarId)) missing from API results, preserving cache",
                    )
                continue
            }

            switch result {
            case let .success(calendarEvents):
                do {
                    try await databaseManager.replaceEvents(for: calendarId, with: calendarEvents)
                    try await databaseManager.updateCalendarSyncTime(calendarId)
                } catch {
                    dbFailedCalendars.append(calendarId)
                    logger.error(
                        "Failed to save events for calendar \(PrivacyUtils.redactedCalendarId(calendarId)): \(error.localizedDescription)",
                    )
                }

            case let .failure(error):
                logger.debug(
                    "API failed for calendar \(PrivacyUtils.redactedCalendarId(calendarId)), preserving cache: \(error.localizedDescription)",
                )
            }
        }
        if !dbFailedCalendars.isEmpty {
            logger.warning(
                "Partial sync: \(dbFailedCalendars.count)/\(selectedCalendarIds.count) calendars failed to save",
            )
        }
        return dbFailedCalendars.count
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
        logger.warning("Network error encountered: \(PrivacyUtils.redactedError(error))")
        guard retryCount < maxRetries else {
            logger.error("Max retries reached, giving up")
            syncStatus = .error("Network error after \(maxRetries) attempts")
            resetRetryCount()
            return
        }

        retryCount += 1
        let retryDelay = calculateRetryDelay()

        logger.info(
            "Network error occurred, retrying in \(retryDelay) seconds (attempt \(self.retryCount)/\(self.maxRetries))",
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
                logger.error("Unexpected retry task error: \(PrivacyUtils.redactedError(error))")
            }
        }
    }

    private func calculateRetryDelay() -> TimeInterval {
        // Exponential backoff with jitter
        let exponentialDelay = baseRetryDelay * pow(Self.backoffBase, Double(retryCount - 1))
        let jitter = Double.random(in: Self.jitterLowerBound ... Self.jitterUpperBound) // +-20% jitter
        return min(exponentialDelay * jitter, Self.maxRetryDelaySeconds) // Cap at 5 minutes
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
}
