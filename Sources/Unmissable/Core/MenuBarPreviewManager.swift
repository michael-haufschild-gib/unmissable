import Foundation
import Observation
import OSLog

@Observable
final class MenuBarPreviewManager {
    private let logger = Logger(category: "MenuBarPreviewManager")

    var menuBarText: String?
    var shouldShowIcon: Bool = true

    @ObservationIgnored
    private let preferencesManager: PreferencesManager
    @ObservationIgnored
    private var events: [Event] = []
    @ObservationIgnored
    private var timerTask: Task<Void, Never>?

    /// Maximum characters shown for a meeting name before truncation.
    private static let maxMeetingNameLength = 12
    /// Number of prefix characters kept when truncating a meeting name.
    private static let truncatedPrefixLength = 9
    /// Seconds per minute, used to convert TimeInterval to minutes.
    private static let secondsPerMinute = 60
    /// Minutes per hour, used for time display formatting.
    private static let minutesPerHour = 60
    /// Minutes per day, used for time display formatting.
    private static let minutesPerDay = 1440

    init(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
        setupBindings()
    }

    private func setupBindings() {
        observeMenuBarDisplayMode()
        // Initial update
        updateMenuBarDisplay()
    }

    private func observeMenuBarDisplayMode() {
        withObservationTracking {
            _ = preferencesManager.menuBarDisplayMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePreferenceChange(preferencesManager.menuBarDisplayMode)
                self.observeMenuBarDisplayMode()
            }
        }
    }

    private func handlePreferenceChange(_ newMode: MenuBarDisplayMode) {
        // IMMEDIATELY stop any running timer to prevent conflicts
        stopTimer()

        // Force immediate update based on new preference - USE THE PARAMETER!
        updateMenuBarDisplay(mode: newMode)
    }

    func updateEvents(_ events: [Event]) {
        self.events = events
        // Only update display if we're not in icon mode, or if this is the first time
        updateMenuBarDisplay()
    }

    private func updateMenuBarDisplay(mode: MenuBarDisplayMode? = nil) {
        let displayMode = mode ?? preferencesManager.menuBarDisplayMode

        switch displayMode {
        case .icon:
            shouldShowIcon = true
            menuBarText = nil
            stopTimer()

        case .timer:
            if let nextMeeting = getNextMeeting() {
                shouldShowIcon = false
                updateTimerDisplay(for: nextMeeting)
                startTimer()
            } else {
                shouldShowIcon = true
                menuBarText = nil
                stopTimer()
            }

        case .nameTimer:
            if let nextMeeting = getNextMeeting() {
                shouldShowIcon = false
                updateNameTimerDisplay(for: nextMeeting)
                startTimer()
            } else {
                shouldShowIcon = true
                menuBarText = nil
                stopTimer()
            }
        }
    }

    /// Returns the most relevant meeting for the timer display:
    /// first any in-progress meeting (started but not ended), then the next upcoming one.
    /// All-day events are excluded — they aren't joinable meetings.
    private func getNextMeeting() -> Event? {
        let now = Date()
        let timedEvents = events.filter { !$0.isAllDay }

        // Prefer an in-progress meeting so the timer shows "Starting" instead of
        // disappearing the moment a meeting begins.
        if let inProgress = timedEvents
            .filter({ $0.startDate <= now && $0.endDate > now })
            .min(by: { $0.startDate < $1.startDate })
        {
            return inProgress
        }

        return timedEvents
            .filter { $0.startDate > now }
            .min { $0.startDate < $1.startDate }
    }

    private func startTimer() {
        stopTimer()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled {
                        updateTimerDisplayIfNeeded()
                    }
                } catch {
                    // Task was cancelled, exit the loop
                    break
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func updateTimerDisplayIfNeeded() {
        // CRITICAL: Only update if we're in a timer mode
        // Never interfere with icon mode regardless of meetings
        let currentMode = preferencesManager.menuBarDisplayMode
        guard currentMode != .icon else {
            // User explicitly wants icon mode - don't change anything
            return
        }

        guard let nextMeeting = getNextMeeting() else {
            // No more meetings, but respect the user's preference mode
            // Show icon but don't change the preference
            shouldShowIcon = true
            menuBarText = nil
            stopTimer()
            return
        }

        // Update display according to current preference
        switch currentMode {
        case .timer:
            updateTimerDisplay(for: nextMeeting)
        case .nameTimer:
            updateNameTimerDisplay(for: nextMeeting)
        case .icon:
            break // Already handled above
        }
    }

    private func updateTimerDisplay(for event: Event) {
        let timeLeft = event.startDate.timeIntervalSince(Date())
        menuBarText = formatTimeLeft(timeLeft)
    }

    private func updateNameTimerDisplay(for event: Event) {
        let timeLeft = event.startDate.timeIntervalSince(Date())
        let truncatedName = truncateMeetingName(event.title)
        let formattedTime = formatTimeLeft(timeLeft)
        menuBarText = "\(truncatedName) \(formattedTime)"
    }

    private func truncateMeetingName(_ name: String) -> String {
        if name.count <= Self.maxMeetingNameLength {
            return name
        }
        let truncated = String(name.prefix(Self.truncatedPrefixLength))
        return "\(truncated)..."
    }

    private func formatTimeLeft(_ timeInterval: TimeInterval) -> String {
        guard timeInterval > 0 else {
            return "Starting"
        }

        let totalMinutes = Int(timeInterval / Double(Self.secondsPerMinute))

        if totalMinutes < 1 { return "< 1 min" }
        if totalMinutes < Self.minutesPerHour { return "\(totalMinutes) min" }
        if totalMinutes < Self.minutesPerDay {
            let hours = totalMinutes / Self.minutesPerHour
            let minutes = totalMinutes % Self.minutesPerHour
            return String(format: "%d:%02d h", hours, minutes)
        }
        let days = totalMinutes / Self.minutesPerDay
        return "\(days) d"
    }

    deinit {
        timerTask?.cancel()
    }
}
