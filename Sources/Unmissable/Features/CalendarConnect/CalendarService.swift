import Combine
import Foundation
import OSLog

@MainActor
final class CalendarService: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "CalendarService")

    @Published var isConnected = false
    @Published var syncStatus: SyncStatus = .idle
    @Published var events: [Event] = []
    @Published var startedEvents: [Event] = []
    @Published var calendars: [CalendarInfo] = []
    @Published var lastSyncTime: Date?
    @Published var nextSyncTime: Date?

    let oauth2Service: OAuth2Service
    private let apiService: GoogleCalendarAPIService
    private let syncManager: SyncManager
    private let databaseManager: DatabaseManager
    private let timezoneManager: TimezoneManager
    private let preferencesManager: PreferencesManager
    private var cancellables = Set<AnyCancellable>()
    private var uiRefreshTask: Task<Void, Never>?

    /// Callback to notify when events need to be rescheduled after sync
    var onEventsUpdated: (() async -> Void)?

    init(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
        oauth2Service = OAuth2Service()
        apiService = GoogleCalendarAPIService(oauth2Service: oauth2Service)
        databaseManager = DatabaseManager.shared
        syncManager = SyncManager(
            apiService: apiService, databaseManager: databaseManager,
            preferencesManager: preferencesManager
        )
        timezoneManager = TimezoneManager.shared

        setupBindings()
        setupSyncCallback()
        startUIRefreshTimer()
    }

    private func setupBindings() {
        // Observe OAuth authentication status
        oauth2Service.$isAuthenticated
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)

        // Observe sync status
        syncManager.$syncStatus
            .assign(to: \.syncStatus, on: self)
            .store(in: &cancellables)

        // Observe sync times
        syncManager.$lastSyncTime
            .assign(to: \.lastSyncTime, on: self)
            .store(in: &cancellables)

        syncManager.$nextSyncTime
            .assign(to: \.nextSyncTime, on: self)
            .store(in: &cancellables)

        // Load cached data on startup
        Task {
            await loadCachedData()
        }

        // Listen for system timezone changes
        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleTimezoneChange()
                }
            }
            .store(in: &cancellables)
    }

    private func setupSyncCallback() {
        // Set up callback to refresh UI after automatic sync completes
        syncManager.onSyncCompleted = { [weak self] in
            await self?.loadCachedData()
            self?.logger.info("🔄 UI refreshed after automatic sync completion")

            // Also notify that events have been updated so alerts can be rescheduled
            await self?.onEventsUpdated?()
            self?.logger.info("📅 Event rescheduling triggered after sync completion")
        }
    }

    func checkConnectionStatus() async {
        logger.info("Checking calendar connection status")

        // Validate auth state on startup to catch expired/invalid tokens early
        await oauth2Service.validateAuthState()

        if isConnected {
            await loadCachedData()
        }
    }

    func connect() async {
        logger.info("Initiating calendar connection")
        do {
            try await oauth2Service.startAuthorizationFlow()

            if isConnected {
                await loadCalendars()
                try await syncManager.syncCalendarList()
                syncManager.startPeriodicSync()
                await loadCachedData()
            }
        } catch {
            logger.error("Calendar connection failed: \(error.localizedDescription)")
            isConnected = false
        }
    }

    func disconnect() async {
        logger.info("Disconnecting from calendar")
        syncManager.stopPeriodicSync()
        stopUIRefreshTimer()
        oauth2Service.signOut()
        events = []
        calendars = []
    }

    func syncEvents() async {
        await syncManager.performSync()
        await loadCachedData()
    }

    func updateCalendarSelection(_ calendarId: String, isSelected: Bool) {
        if let index = calendars.firstIndex(where: { $0.id == calendarId }) {
            calendars[index] = calendars[index].withSelection(isSelected)

            logger.info("Updated calendar \(calendarId) selection to \(isSelected)")

            // Save to database
            Task {
                try await databaseManager.saveCalendars([calendars[index]])
            }

            // Trigger a sync if we're connected
            if isConnected {
                Task {
                    await syncEvents()
                }
            }
        }
    }

    private func loadCalendars() async {
        do {
            try await apiService.fetchCalendars()
            // Convert API calendars to local models
            calendars = apiService.calendars
            logger.info("Loaded \(calendars.count) calendars")
        } catch {
            logger.error("Failed to load calendars: \(error.localizedDescription)")
        }
    }

    private func loadCachedData() async {
        do {
            // Load calendars from database
            let cachedCalendars = try await databaseManager.fetchCalendars()
            if !cachedCalendars.isEmpty {
                calendars = cachedCalendars
            }

            // Load upcoming events from database
            let cachedEvents = try await databaseManager.fetchUpcomingEvents(limit: 50)

            // Load started meetings from database
            let cachedStartedEvents = try await databaseManager.fetchStartedMeetings(limit: 20)

            events = cachedEvents.map { timezoneManager.localizedEvent($0) }
            startedEvents = cachedStartedEvents.map { timezoneManager.localizedEvent($0) }

            logger.info(
                "Loaded \(calendars.count) calendars, \(events.count) upcoming events, and \(startedEvents.count) started meetings from cache"
            )
        } catch {
            logger.error("Failed to load cached data: \(error.localizedDescription)")
        }
    }

    private func handleTimezoneChange() async {
        logger.info("Handling timezone change")
        // Reload events to reflect new system timezone in any formatted strings
        await loadCachedData()
    }

    // MARK: - Search and Queries

    func searchEvents(query: String) async throws -> [Event] {
        let results = try await syncManager.searchEvents(query: query)
        return results.map { timezoneManager.localizedEvent($0) }
    }

    func getEventsForToday() async throws -> [Event] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        let results = try await syncManager.getEventsInRange(from: today, to: tomorrow)
        return results.map { timezoneManager.localizedEvent($0) }
    }

    func getUpcomingEvents(limit: Int = 10) async throws -> [Event] {
        let results = try await syncManager.getUpcomingEvents(limit: limit)
        return results.map { timezoneManager.localizedEvent($0) }
    }

    // MARK: - Public Accessors

    var syncManagerPublic: SyncManager {
        syncManager
    }

    // MARK: - UI Refresh Timer

    private func startUIRefreshTimer() {
        // Start a timer that refreshes UI events every 30 seconds
        // This ensures real-time updates for time-dependent UI elements like join buttons
        uiRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                    if !Task.isCancelled {
                        await refreshUIEvents()
                    }
                } catch {
                    // Task was cancelled, exit the loop
                    break
                }
            }
        }
        logger.info("✅ UI refresh timer started (30 second interval)")
    }

    private func stopUIRefreshTimer() {
        uiRefreshTask?.cancel()
        uiRefreshTask = nil
        logger.info("⏹️ UI refresh timer stopped")
    }

    private func refreshUIEvents() async {
        // Refresh events from database to update time-dependent UI elements
        // without triggering a full calendar sync
        await loadCachedData()
    }
}
