import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class EventScheduler: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "EventScheduler")

    @Published var scheduledAlerts: [ScheduledAlert] = []

    nonisolated(unsafe) private var monitoringTask: Task<Void, Never>?
    private let preferencesManager: PreferencesManager
    nonisolated(unsafe) private var cancellables = Set<AnyCancellable>()

    // Store current events to allow rescheduling
    private var currentEvents: [Event] = []
    private weak var currentOverlayManager: OverlayManager?

    init(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
        setupPreferencesObserver()
    }

    deinit {
        // Capture nonisolated(unsafe) properties to local constants to avoid data race.
        // The capture itself is atomic (reading a reference), avoiding the race condition.
        // Task.cancel() and AnyCancellable.cancel() are both thread-safe operations,
        // so we can safely call them synchronously from any thread.
        let task = monitoringTask
        let subs = cancellables
        task?.cancel()
        subs.forEach { $0.cancel() }
    }

    private func setupPreferencesObserver() {
        // Watch for alert timing preference changes
        Publishers.CombineLatest4(
            preferencesManager.$overlayShowMinutesBefore,
            preferencesManager.$useLengthBasedTiming,
            preferencesManager.$defaultAlertMinutes,
            preferencesManager.$shortMeetingAlertMinutes
        )
        .sink { [weak self] _, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                logger.info("🔔 Alert preferences changed, rescheduling alerts")
                await rescheduleCurrentAlerts()
            }
        }
        .store(in: &cancellables)

        // Also watch for medium and long meeting alert changes
        Publishers.CombineLatest(
            preferencesManager.$mediumMeetingAlertMinutes,
            preferencesManager.$longMeetingAlertMinutes
        )
        .sink { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                logger.info("🔔 Alert preferences changed, rescheduling alerts")
                await rescheduleCurrentAlerts()
            }
        }
        .store(in: &cancellables)
    }

    func startScheduling(events: [Event], overlayManager: OverlayManager) async {
        logger.info("🚀 Starting event scheduling for \(events.count) events")

        // Log the first few events for debugging
        for (index, event) in events.prefix(3).enumerated() {
            logger.info("  📅 Event \(index + 1): '\(event.title)' at \(event.startDate)")
        }

        // Store for future rescheduling when preferences change
        currentEvents = events
        currentOverlayManager = overlayManager

        stopTimers()
        scheduleAlerts(for: events)
        startMonitoring(overlayManager: overlayManager)

        logger.info("✅ Event scheduling setup completed")
    }

    private func rescheduleCurrentAlerts() async {
        guard !currentEvents.isEmpty, let overlayManager = currentOverlayManager else {
            logger.info("No current events to reschedule")
            return
        }

        logger.info(
            "Rescheduling alerts for \(currentEvents.count) events with updated preferences"
        )

        stopTimers()
        scheduleAlerts(for: currentEvents)
        startMonitoring(overlayManager: overlayManager)
    }

    func stopScheduling() {
        logger.info("🛑 STOP SCHEDULING: Starting cleanup")
        stopTimers()

        // Clean up properly to prevent memory leaks
        currentEvents.removeAll()
        currentOverlayManager = nil

        logger.info("✅ STOP SCHEDULING: Cleanup completed")
    }

    private func stopTimers() {
        // Cancel the monitoring task
        monitoringTask?.cancel()
        monitoringTask = nil
        scheduledAlerts.removeAll()
    }

    private func scheduleAlerts(for events: [Event]) {
        // Preserve existing snooze alerts before clearing
        let existingSnoozeAlerts = scheduledAlerts.filter { alert in
            if case .snooze = alert.alertType {
                return alert.triggerDate > Date() // Only keep future snooze alerts
            }
            return false
        }

        scheduledAlerts.removeAll()

        let currentTime = Date()

        for event in events {
            // Skip events that have already ended
            if event.endDate < currentTime {
                continue
            }

            // Schedule overlay alerts based on preferences
            let overlayTiming = preferencesManager.overlayShowMinutesBefore
            let overlayTime = event.startDate.addingTimeInterval(-TimeInterval(overlayTiming * 60))

            if overlayTime > currentTime {
                let overlayAlert = ScheduledAlert(
                    event: event,
                    triggerDate: overlayTime,
                    alertType: .reminder(minutesBefore: overlayTiming)
                )
                scheduledAlerts.append(overlayAlert)
            } else if event.startDate > currentTime {
                // Alert time has passed but meeting hasn't started (e.g. app started late)
                // Show overlay immediately if we have a manager
                if let manager = currentOverlayManager {
                    logger.info("⚠️ Missed alert time for \(event.title), triggering immediately")
                    manager.showOverlay(for: event, minutesBeforeMeeting: overlayTiming, fromSnooze: false)
                }
            }

            // Schedule sound alerts if enabled (using event-specific timing)
            if preferencesManager.soundEnabled {
                let soundTiming = preferencesManager.alertMinutes(for: event)
                let soundTime = event.startDate.addingTimeInterval(-TimeInterval(soundTiming * 60))

                if soundTime > currentTime, soundTime != overlayTime {
                    let soundAlert = ScheduledAlert(
                        event: event,
                        triggerDate: soundTime,
                        alertType: .reminder(minutesBefore: soundTiming)
                    )
                    scheduledAlerts.append(soundAlert)
                }
            }
        }

        // Re-add preserved snooze alerts
        scheduledAlerts.append(contentsOf: existingSnoozeAlerts)

        // Sort by trigger time
        scheduledAlerts.sort { $0.triggerDate < $1.triggerDate }

        logger.info(
            "Scheduled \(scheduledAlerts.count) alerts (including \(existingSnoozeAlerts.count) preserved snooze alerts)"
        )
    }

    private func startMonitoring(overlayManager: OverlayManager) {
        // Cancel existing task if any
        monitoringTask?.cancel()

        monitoringTask = Task { @MainActor in
            logger.info("👀 MONITORING: Starting smart alert monitoring")

            while !Task.isCancelled {
                do {
                    guard let nextAlert = scheduledAlerts.first else {
                        logger.info("💤 MONITORING: No alerts scheduled, waiting for updates...")
                        // Wait indefinitely until task is cancelled (which happens on reschedule)
                        try await Task.sleep(for: .seconds(3600))
                        continue
                    }

                    let now = Date()
                    let timeUntilTrigger = nextAlert.triggerDate.timeIntervalSince(now)

                    if timeUntilTrigger > 0.1 {
                        logger
                            .debug(
                                "⏳ MONITORING: Sleeping for \(String(format: "%.2f", timeUntilTrigger))s until next alert for '\(nextAlert.event.title)'"
                            )
                        // Sleep exactly until the next alert (plus a tiny buffer)
                        try await Task.sleep(for: .seconds(timeUntilTrigger))
                    }

                    // Double check cancellation before processing
                    guard !Task.isCancelled else { break }

                    // Process triggers
                    await checkForTriggeredAlerts(overlayManager: overlayManager)
                } catch {
                    // Task cancellation throws cancellation error
                    if Task.isCancelled {
                        logger.info("🛑 MONITORING: Task cancelled")
                        break
                    }
                    logger.error("❌ MONITORING: Error in loop: \(error.localizedDescription)")
                    // Prevent rapid error looping
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    /// Restarts the monitoring task to pick up new alerts immediately
    private func refreshMonitoring() {
        guard let overlayManager = currentOverlayManager else { return }
        logger.debug("🔄 MONITORING: Refreshing monitor task")
        startMonitoring(overlayManager: overlayManager)
    }

    private func checkForTriggeredAlerts(overlayManager: OverlayManager) async {
        let now = Date()

        // Find alerts that should trigger
        let triggeredAlerts = scheduledAlerts.filter { alert in
            alert.triggerDate <= now
        }

        if !triggeredAlerts.isEmpty {
            logger.info("🔔 Found \(triggeredAlerts.count) triggered alerts at \(now)")
            for alert in triggeredAlerts {
                let alertTypeName = switch alert.alertType {
                case let .reminder(minutes):
                    "reminder(\(minutes)min)"
                case let .snooze(until):
                    "snooze(until: \(until))"
                case .meetingStart:
                    "meetingStart"
                }
                logger.info(
                    "  - \(alertTypeName) for '\(alert.event.title)' (trigger: \(alert.triggerDate))"
                )
            }
        }

        for alert in triggeredAlerts {
            await handleTriggeredAlert(alert, overlayManager: overlayManager)
        }

        // Remove triggered alerts
        let beforeCount = scheduledAlerts.count
        scheduledAlerts.removeAll { alert in
            triggeredAlerts.contains { $0.id == alert.id }
        }

        if !triggeredAlerts.isEmpty {
            let afterCount = scheduledAlerts.count
            logger.info(
                "✅ Processed \(triggeredAlerts.count) alerts, \(afterCount) remaining scheduled (was \(beforeCount))"
            )
        }
    }

    private func handleTriggeredAlert(_ alert: ScheduledAlert, overlayManager: OverlayManager) async {
        let alertTypeName = switch alert.alertType {
        case let .reminder(minutes):
            "reminder(\(minutes)min)"
        case let .snooze(until):
            "snooze(until: \(until))"
        case .meetingStart:
            "meetingStart"
        }

        logger.info("🚨 HANDLING ALERT: \(alertTypeName) for event: \(alert.event.title)")

        // CRITICAL FIX: Ensure all overlay operations happen on main thread
        await MainActor.run {
            switch alert.alertType {
            case .reminder:
                logger.info("📱 REMINDER: Showing overlay for \(alert.event.title)")
                overlayManager.showOverlay(for: alert.event, fromSnooze: false)

            case .meetingStart:
                if preferencesManager.autoJoinEnabled, let url = alert.event.primaryLink {
                    logger.info("🚀 AUTO-JOIN: Opening meeting for \(alert.event.title)")
                    NSWorkspace.shared.open(url)
                }

            case .snooze:
                logger.info("⏰ SNOOZE: Re-showing overlay for \(alert.event.title)")
                // SNOOZE FIX: Mark overlay as coming from snooze alert
                overlayManager.showOverlay(for: alert.event, fromSnooze: true)
            }
        }

        logger.info("✅ ALERT HANDLED: Completed for \(alert.event.title)")
    }

    func scheduleSnooze(for event: Event, minutes: Int) {
        let snoozeDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let meetingStarted = event.startDate < Date()

        // Allow snoozing past meeting start time - user might want to join late
        // Don't limit to meeting start time like the original logic
        let snoozeAlert = ScheduledAlert(
            event: event,
            triggerDate: snoozeDate, // Use full snooze time, not limited by meeting start
            alertType: .snooze(until: snoozeDate)
        )

        scheduledAlerts.append(snoozeAlert)
        scheduledAlerts.sort { $0.triggerDate < $1.triggerDate }

        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none

        if meetingStarted {
            logger.info(
                "⏰ Scheduled snooze for \(minutes) minutes for event '\(event.title)' (meeting already started). Will trigger at \(formatter.string(from: snoozeDate))"
            )
        } else {
            logger.info(
                "⏰ Scheduled snooze for \(minutes) minutes for event '\(event.title)' (meeting starts later). Will trigger at \(formatter.string(from: snoozeDate))"
            )
        }

        // Restart monitoring to ensure we wake up for this snooze if it's next
        refreshMonitoring()
    }
}
