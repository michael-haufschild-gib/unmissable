import EventKit
import Foundation
import OSLog

// MARK: - Deduplication, UI Refresh Timer & EKEventStoreChanged Observer

extension CalendarService {
    /// Seconds to debounce EKEventStoreChanged notifications. Apple Calendar
    /// can fire rapid bursts during iCloud sync; collapsing to one sync is sufficient.
    static let ekChangedDebounceSeconds: TimeInterval = 2.0
    /// Maximum idle sleep when no events are loaded or no boundaries are near.
    static let uiRefreshMaxIdleSeconds: TimeInterval = 60
    /// Minimum sleep to avoid busy-looping when a boundary is imminent.
    static let uiRefreshMinSleepSeconds: TimeInterval = 5

    // MARK: - EKEventStoreChanged

    /// Subscribes to EKEventStoreChanged so Apple Calendar data changes
    /// (local edits, iCloud sync) trigger a reactive sync without waiting
    /// for the next periodic interval.
    func setupEventStoreChangeObserver() {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: sharedEventStore)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleEventStoreChanged()
                }
            }
            .store(in: &cancellables)
    }

    func handleEventStoreChanged() {
        // Only relevant if an Apple Calendar provider is connected
        guard let appleBackend = providers[.apple],
              appleBackend.auth.isAuthenticated
        else { return }

        // Debounce: cancel any pending sync, start a new delay
        ekChangedDebounceTask?.cancel()
        ekChangedDebounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.ekChangedDebounceSeconds))
            } catch {
                return // Cancelled by a newer notification — expected
            }

            guard let self, !Task.isCancelled else { return }
            guard let appleBackend = self.providers[.apple],
                  appleBackend.auth.isAuthenticated
            else { return }

            self.logger.info("EKEventStoreChanged: triggering Apple Calendar sync")
            await appleBackend.sync.performSync()
        }
    }

    // MARK: - Deduplication

    /// Removes cross-provider duplicates where the same meeting is synced from
    /// both Apple Calendar and Google Calendar. Keeps the event with the most
    /// meeting links (better for one-click join UX).
    static func deduplicateEvents(_ events: [Event]) -> [Event] {
        var seen: [String: Int] = [:] // dedup key → index in result
        var result: [Event] = []

        for event in events {
            let key = "\(event.title.trimmingCharacters(in: .whitespaces))|\(event.startDate.timeIntervalSince1970)|\(event.endDate.timeIntervalSince1970)"

            if let existingIndex = seen[key] {
                // Keep whichever has more meeting links
                if event.links.count > result[existingIndex].links.count {
                    result[existingIndex] = event
                }
            } else {
                seen[key] = result.count
                result.append(event)
            }
        }

        return result
    }

    // MARK: - UI Refresh Timer

    /// Whether any event crossed a time boundary (started or ended) since the arrays were last loaded.
    ///
    /// Compares the current set of event IDs that would be in each category (upcoming vs. started)
    /// against the IDs captured at the last `loadCachedData()` call. Returns true only when the
    /// composition has actually changed — i.e., an event crossed from upcoming to started, or a
    /// started event ended. This replaces the previous check (`startDate <= now`) which returned
    /// true permanently once any event had started, triggering unnecessary DB reads every cycle.
    func hasTimeBoundaryChange() -> Bool {
        let now = Date()
        let currentUpcomingIDs = Set(events.filter { $0.startDate > now }.map(\.id))
        let currentStartedIDs = Set(startedEvents.filter { $0.endDate > now }.map(\.id))
        return currentUpcomingIDs != lastLoadedUpcomingIDs
            || currentStartedIDs != lastLoadedStartedIDs
    }

    func startUIRefreshTimer() {
        // Cancel any existing timer to prevent duplicate loops (defensive).
        stopUIRefreshTimer()

        uiRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    let sleepInterval = nextBoundaryInterval()
                    try await Task.sleep(for: .seconds(sleepInterval))
                    if !Task.isCancelled, needsUIRefresh || hasTimeBoundaryChange() {
                        if await loadCachedData() {
                            needsUIRefresh = false
                        }
                    }
                } catch {
                    break
                }
            }
        }
        logger.debug("UI refresh timer started")
    }

    /// Computes the optimal sleep interval until the next event time boundary.
    /// Returns the time until the earliest upcoming event starts or the earliest
    /// started event ends, clamped to [5, 60] seconds. This replaces fixed 30s
    /// polling, reducing wake-ups when events are far away while staying responsive
    /// near boundaries.
    func nextBoundaryInterval() -> TimeInterval {
        let now = Date()
        var nearest = Self.uiRefreshMaxIdleSeconds

        // Next upcoming event start
        if let firstUpcoming = events.first(where: { $0.startDate > now }) {
            let untilStart = firstUpcoming.startDate.timeIntervalSince(now)
            nearest = min(nearest, untilStart)
        }

        // Nearest started event end (startedEvents is sorted by startDate desc,
        // not endDate, so we must scan all to find the soonest end boundary)
        if let nearestEnd = startedEvents
            .filter({ $0.endDate > now })
            .map(\.endDate)
            .min()
        {
            let untilEnd = nearestEnd.timeIntervalSince(now)
            nearest = min(nearest, untilEnd)
        }

        return max(Self.uiRefreshMinSleepSeconds, min(nearest, Self.uiRefreshMaxIdleSeconds))
    }

    func stopUIRefreshTimer() {
        uiRefreshTask?.cancel()
        uiRefreshTask = nil
        logger.debug("UI refresh timer stopped")
    }
}
