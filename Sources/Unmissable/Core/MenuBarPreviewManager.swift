import Combine
import Foundation
import OSLog

@MainActor
final class MenuBarPreviewManager: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "MenuBarPreviewManager")

    @Published var menuBarText: String? = nil
    @Published var shouldShowIcon: Bool = true

    private let preferencesManager: PreferencesManager
    private var events: [Event] = []
    private var timerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
        setupBindings()
    }

    private func setupBindings() {
        // Observe preference changes - this should IMMEDIATELY update the display
        preferencesManager.$menuBarDisplayMode
            .sink { [weak self] newMode in
                self?.handlePreferenceChange(newMode)
            }
            .store(in: &cancellables)

        // Initial update
        updateMenuBarDisplay()
    }

    private func handlePreferenceChange(_ newMode: MenuBarDisplayMode) {
        // IMMEDIATELY stop any running timer to prevent conflicts
        stopTimer()

        // Force immediate update based on new preference - USE THE PARAMETER!
        updateMenuBarDisplay(mode: newMode)

        // Force UI update by explicitly triggering @Published notifications
        Task { @MainActor in
            self.objectWillChange.send()
        }
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

    private func getNextMeeting() -> Event? {
        let now = Date()
        return
            events
                .filter { $0.startDate > now }
                .sorted { $0.startDate < $1.startDate }
                .first
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
        if name.count <= 12 {
            return name
        }
        let truncated = String(name.prefix(9))
        return "\(truncated)..."
    }

    private func formatTimeLeft(_ timeInterval: TimeInterval) -> String {
        guard timeInterval > 0 else {
            return "Starting"
        }

        let totalMinutes = Int(timeInterval / 60)

        if totalMinutes < 1 {
            return "< 1 min"
        } else if totalMinutes < 60 {
            return "\(totalMinutes) min"
        } else if totalMinutes < 1440 { // Less than 24 hours
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return String(format: "%d:%02d h", hours, minutes)
        } else {
            let days = totalMinutes / 1440
            return "\(days) d"
        }
    }

    deinit {
        timerTask?.cancel()
    }
}
