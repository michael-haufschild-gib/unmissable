import Combine
import Foundation
import Network
import OSLog

@MainActor
final class SyncManager: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "SyncManager")

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
    private let databaseManager: DatabaseManager
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

    init(
        apiService: any CalendarAPIProviding, databaseManager: DatabaseManager,
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
                try await Task.sleep(for: .milliseconds(Int(networkDebounceDelay * 1000)))
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
                    try await Task.sleep(for: .seconds(Int(intervalSeconds)))
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

    func performSync() async {
        guard isOnline else {
            logger.debug("Skipping sync - device is offline")
            syncStatus = .offline
            return
        }

        guard syncStatus != .syncing else {
            logger.debug("Sync already in progress, skipping")
            return
        }

        syncStatus = .syncing
        logger.debug("Starting calendar sync (attempt \(self.retryCount + 1))")

        do {
            let calendars = try await databaseManager.fetchCalendars()
            let selectedCalendarIds = calendars.filter(\.isSelected).map(\.id)

            guard !selectedCalendarIds.isEmpty else {
                logger.warning("No calendars selected for sync")
                syncStatus = .idle
                updateSyncTimes()
                resetRetryCount()
                return
            }

            let now = Date()
            let startOfDay = Calendar.current.startOfDay(for: now)
            let endDate = Calendar.current.date(byAdding: .day, value: self.eventLookAheadDays, to: now) ?? now

            await apiService.fetchEvents(
                for: selectedCalendarIds,
                from: startOfDay,
                to: endDate
            )

            let fetchedEvents = apiService.events

            if fetchedEvents.isEmpty, let apiError = apiService.lastError {
                throw SyncError.apiFetchFailed(apiError)
            }

            let eventsByCalendar = Dictionary(grouping: fetchedEvents) { $0.calendarId }

            _ = await saveEventsPerCalendar(
                eventsByCalendar: eventsByCalendar,
                selectedCalendarIds: selectedCalendarIds
            )

            syncStatus = .idle
            updateSyncTimes()
            resetRetryCount()

            logger.info("Sync completed: \(fetchedEvents.count) events from \(selectedCalendarIds.count) calendars")

            await onSyncCompleted?()
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")

            if isNetworkError(error) {
                handleNetworkError(error)
            } else {
                syncStatus = .error(error.localizedDescription)
                resetRetryCount()
            }

            updateNextSyncTime()
        }
    }

    private func saveEventsPerCalendar(
        eventsByCalendar: [String: [Event]],
        selectedCalendarIds: [String]
    ) async -> Int {
        logger.debug("Saving events to database (transactional per calendar)")
        var failedCalendars: [String] = []
        for calendarId in selectedCalendarIds {
            let calendarEvents = eventsByCalendar[calendarId] ?? []
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
        // Check for common network error patterns
        let nsError = error as NSError

        return nsError.domain == NSURLErrorDomain || nsError.code == NSURLErrorNotConnectedToInternet
            || nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorCannotConnectToHost
            || nsError.code == NSURLErrorNetworkConnectionLost
    }

    private func handleNetworkError(_: Error) {
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
                try await Task.sleep(for: .seconds(Int(retryDelay)))
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

    func syncCalendarList() async throws {
        logger.debug("Syncing calendar list")

        try await apiService.fetchCalendars()

        // Convert API calendars to database models, preserving sourceProvider
        let dbCalendars = apiService.calendars.map { calendar in
            CalendarInfo(
                id: calendar.id,
                name: calendar.name,
                description: calendar.description,
                isSelected: calendar.isSelected,
                isPrimary: calendar.isPrimary,
                colorHex: calendar.colorHex,
                sourceProvider: calendar.sourceProvider,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        try await databaseManager.saveCalendars(dbCalendars)
        logger.debug("Calendar list synced: \(dbCalendars.count) calendars")
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
        if let lastSync = lastManualSyncTime {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            if timeSinceLastSync < minSyncCooldown {
                let remainingCooldown = Int(minSyncCooldown - timeSinceLastSync)
                logger.debug("Manual sync rate limited - \(remainingCooldown)s remaining")
                return
            }
        }

        logger.debug("Force sync requested")
        lastManualSyncTime = Date()
        await performSync()
    }

    func refreshCalendarList() async throws {
        logger.debug("Refresh calendar list requested")
        try await syncCalendarList()
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
