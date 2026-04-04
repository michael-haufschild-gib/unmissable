import AppKit
import Foundation
import Observation
import OSLog

@Observable
final class EventScheduler {
    private let logger = Logger(category: "EventScheduler")

    var scheduledAlerts: [ScheduledAlert] = []

    @ObservationIgnored
    private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored
    private let preferencesManager: PreferencesManager
    @ObservationIgnored
    private let linkParser: LinkParser

    // Store current events to allow rescheduling
    private var currentEvents: [Event] = []
    private weak var currentOverlayManager: (any OverlayManaging)?

    /// Per-event alert overrides, keyed by event ID. Values are minutes
    /// before start (0 = suppress all alerts). Loaded from the database
    /// by AppState and passed in via `updateAlertOverrides`.
    private var alertOverrides: [String: Int] = [:]

    /// Per-calendar alert modes, keyed by calendar ID. Controls whether alerts
    /// use overlay, notification, or are suppressed. Loaded from the database
    /// by AppState and passed in via `updateCalendarAlertModes`.
    private var calendarAlertModes: [String: AlertMode] = [:]

    /// Optional notification manager for delivering Notification Center alerts.
    /// Nil when notifications are not configured (e.g. tests).
    private var notificationManager: (any NotificationManaging)?

    /// Whether monitoring was explicitly started via `startScheduling`.
    /// `scheduleWithoutMonitoring` sets this to false, preventing
    /// `refreshMonitoring` from starting a loop. Used by tests that
    /// don't need the monitoring loop.
    private var monitoringEnabled = false

    /// Abstraction over `Task.sleep` for deterministic testing.
    /// Production default sleeps for the given number of seconds.
    private let sleepForSeconds: @Sendable (TimeInterval) async throws -> Void

    /// Abstraction over `Date()` for deterministic testing.
    /// Production default returns the current wall-clock time.
    private let now: @Sendable () -> Date

    /// Number of events logged on scheduling start for debugging.
    private static let debugLogEventCount = 3
    /// Seconds per minute, used for time conversions.
    private static let secondsPerMinute: TimeInterval = 60
    /// Idle sleep interval (seconds) when no alerts are scheduled.
    private static let idleSleepSeconds: TimeInterval = 30
    /// Minimum time-until-trigger threshold (seconds) below which we fire immediately.
    private static let triggerThresholdSeconds: TimeInterval = 0.1
    /// Sleep duration after an unexpected monitoring error (seconds) to avoid tight loops.
    private static let errorRecoverySleepSeconds: TimeInterval = 5

    init(
        preferencesManager: PreferencesManager,
        linkParser: LinkParser,
        sleepForSeconds: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.preferencesManager = preferencesManager
        self.linkParser = linkParser
        self.sleepForSeconds = sleepForSeconds
        self.now = now
        setupPreferencesObserver()
    }

    private func setupPreferencesObserver() {
        observeAlertPreferences()
    }

    private func observeAlertPreferences() {
        withObservationTracking {
            // Touch all preference properties that affect alert scheduling
            _ = preferencesManager.overlayShowMinutesBefore
            _ = preferencesManager.useLengthBasedTiming
            _ = preferencesManager.defaultAlertMinutes
            _ = preferencesManager.shortMeetingAlertMinutes
            _ = preferencesManager.mediumMeetingAlertMinutes
            _ = preferencesManager.longMeetingAlertMinutes
            _ = preferencesManager.playAlertSound
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                logger.info("Alert preferences changed, rescheduling alerts")
                rescheduleCurrentAlerts()
                observeAlertPreferences()
            }
        }
    }

    func startScheduling(events: [Event], overlayManager: any OverlayManaging) {
        monitoringEnabled = true
        scheduleWithoutMonitoring(events: events, overlayManager: overlayManager)
        startMonitoring(overlayManager: overlayManager)
        logger.debug("Event scheduling setup completed")
        AppDiagnostics.record(component: "EventScheduler", phase: "startScheduling") {
            [
                "events": "\(events.count)",
                "alerts": "\(self.scheduledAlerts.count)",
                "monitoring": "true",
            ]
        }
    }

    /// Schedules alerts and fires missed overlays, but does NOT start the
    /// monitoring loop. Used by tests that verify alert scheduling without
    /// needing the monitoring loop (which requires a TestClock to advance).
    func scheduleWithoutMonitoring(events: [Event], overlayManager: any OverlayManaging) {
        monitoringEnabled = false
        logger.info("Scheduling alerts for \(events.count) events")

        for (index, event) in events.prefix(Self.debugLogEventCount).enumerated() {
            logger.debug("  Event \(index + 1): id=\(event.id) at \(event.startDate)")
        }

        currentEvents = events
        currentOverlayManager = overlayManager

        stopTimers(preserveSnoozes: true)
        let missedEvents = scheduleAlerts(for: events)
        for event in missedEvents {
            logger.info("Missed alert time for event \(event.id), triggering immediately")
            deliverAlert(for: event, overlayManager: overlayManager, fromSnooze: false)
        }
    }

    /// Updates the per-event alert override dictionary and triggers a reschedule
    /// if events are currently being tracked.
    func updateAlertOverrides(_ overrides: [String: Int]) {
        alertOverrides = overrides
        rescheduleCurrentAlerts()
    }

    /// Updates the per-calendar alert mode dictionary. Does not reschedule —
    /// modes affect routing at trigger time, not scheduling time.
    func updateCalendarAlertModes(_ modes: [String: AlertMode]) {
        calendarAlertModes = modes
    }

    /// Injects the notification manager for delivering Notification Center alerts.
    func setNotificationManager(_ manager: any NotificationManaging) {
        notificationManager = manager
    }

    private func rescheduleCurrentAlerts() {
        guard !currentEvents.isEmpty, let overlayManager = currentOverlayManager else {
            logger.debug("No current events to reschedule")
            return
        }

        logger.debug(
            "Rescheduling alerts for \(self.currentEvents.count) events with updated preferences",
        )

        // Cancel monitoring but don't clear scheduledAlerts — scheduleAlerts()
        // preserves existing snooze alerts before rebuilding the alert list
        monitoringTask?.cancel()
        monitoringTask = nil
        let missedEvents = scheduleAlerts(for: currentEvents)
        for event in missedEvents {
            logger.info("Missed alert time for event \(event.id), triggering immediately")
            deliverAlert(for: event, overlayManager: overlayManager, fromSnooze: false)
        }
        if monitoringEnabled {
            startMonitoring(overlayManager: overlayManager)
        }
    }

    func stopScheduling() {
        logger.debug("Stopping event scheduling")
        monitoringEnabled = false
        stopTimers()

        // Clean up properly to prevent memory leaks
        currentEvents.removeAll()
        currentOverlayManager = nil

        logger.debug("Event scheduling stopped")
    }

    private func stopTimers(preserveSnoozes: Bool = false) {
        // Cancel the monitoring task
        monitoringTask?.cancel()
        monitoringTask = nil
        if preserveSnoozes {
            // Keep snooze alerts so they survive startScheduling calls
            // (e.g. after calendar sync refreshes the event list)
            scheduledAlerts.removeAll { alert in
                if case .snooze = alert.alertType { return false }
                return true
            }
        } else {
            scheduledAlerts.removeAll()
        }
    }

    /// Returns events whose alert time has already passed but whose meeting has not yet started.
    /// The caller is responsible for showing overlays for these events.
    private func scheduleAlerts(for events: [Event]) -> [Event] {
        // Preserve existing snooze alerts before clearing.
        // Only keep snoozes for events that are still schedulable (non-all-day, present in
        // current event list) to prevent stale snoozes from surviving reclassification.
        let schedulableEventIDs = Set(events.filter { !$0.isAllDay }.map(\.id))
        let existingSnoozeAlerts = scheduledAlerts.filter { alert in
            if case .snooze = alert.alertType {
                return alert.triggerDate > now() && schedulableEventIDs.contains(alert.event.id)
            }
            return false
        }

        scheduledAlerts.removeAll()

        let currentTime = now()
        var missedAlertEvents: [Event] = []

        for event in events {
            // Skip all-day events — they aren't joinable meetings
            if event.isAllDay { continue }

            // Skip events that have already ended
            if event.endDate < currentTime {
                continue
            }

            // Check for per-event alert override (compound key: eventId_calendarId)
            let overrideKey = EventOverride.compoundKey(
                eventId: event.id, calendarId: event.calendarId,
            )
            let eventOverride = alertOverrides[overrideKey]

            // Override of 0 means "no alert" — skip all scheduling for this event
            if eventOverride == 0 { continue }

            // When an override is set, it controls both overlay and sound timing.
            // When no override, overlay uses global `overlayShowMinutesBefore` and
            // sound uses length-based/default timing via `alertMinutes(for:)`.
            let overlayTiming = eventOverride ?? preferencesManager.overlayShowMinutesBefore
            let overlayTime = event.startDate.addingTimeInterval(
                -TimeInterval(overlayTiming) * Self.secondsPerMinute,
            )

            if overlayTime > currentTime {
                let overlayAlert = ScheduledAlert(
                    event: event,
                    triggerDate: overlayTime,
                    alertType: .reminder(minutesBefore: overlayTiming),
                )
                scheduledAlerts.append(overlayAlert)
            } else if event.startDate > currentTime {
                // Alert time has passed but meeting hasn't started (e.g. app started late)
                missedAlertEvents.append(event)
            }
            // Implicit else: event already started (startDate <= now).
            // Intentionally no overlay — a retroactive blocking overlay for an
            // in-progress meeting would be disorienting. The menu bar shows
            // "Starting" for these events; snoozed alerts are preserved separately.

            // Schedule a secondary reminder at length-based timing (if it differs from overlay timing).
            // Despite the historical name "sound alert", this is another .reminder that routes through
            // deliverAlert → showOverlay (which plays sound internally). If the first overlay is still
            // visible when this fires, showOverlay's duplicate check silently drops it. The net effect:
            // if the user dismisses the first overlay early, they get a second reminder closer to start.
            // When an override is set, a single alert at the override time is sufficient.
            if preferencesManager.soundEnabled, eventOverride == nil {
                let soundTiming = preferencesManager.alertMinutes(for: event)
                let soundTime = event.startDate.addingTimeInterval(
                    -TimeInterval(soundTiming) * Self.secondsPerMinute,
                )

                if soundTime > currentTime, soundTime != overlayTime {
                    let soundAlert = ScheduledAlert(
                        event: event,
                        triggerDate: soundTime,
                        alertType: .reminder(minutesBefore: soundTiming),
                    )
                    scheduledAlerts.append(soundAlert)
                }
            }
        }

        // Re-add preserved snooze alerts
        scheduledAlerts.append(contentsOf: existingSnoozeAlerts)

        // Sort by trigger time
        scheduledAlerts.sort { $0.triggerDate < $1.triggerDate }

        logger.debug(
            "Scheduled \(self.scheduledAlerts.count) alerts (including \(existingSnoozeAlerts.count) preserved snooze alerts)",
        )

        AppDiagnostics.record(component: "EventScheduler", phase: "scheduleAlerts") {
            [
                "inputEvents": "\(events.count)",
                "scheduledAlerts": "\(self.scheduledAlerts.count)",
                "preservedSnoozes": "\(existingSnoozeAlerts.count)",
                "missedAlerts": "\(missedAlertEvents.count)",
                "skippedAllDay": "\(events.filter(\.isAllDay).count)",
                "skippedEnded": "\(events.count(where: { $0.endDate < currentTime }))",
            ]
        }

        return missedAlertEvents
    }

    /// Maximum acceptable drift between expected and actual wake time before
    /// treating the gap as a system sleep/wake event (seconds).
    private static let wakeDriftThreshold: TimeInterval = 2.0

    private func startMonitoring(overlayManager: any OverlayManaging) {
        // Cancel existing task if any
        monitoringTask?.cancel()

        monitoringTask = Task { @MainActor [weak self] in
            self?.logger.debug("Alert monitoring started")

            while !Task.isCancelled {
                guard let self else { break }
                do {
                    guard let nextAlert = scheduledAlerts.first else {
                        logger.debug("No alerts scheduled, waiting for updates")
                        // Short sleep so newly-added events are picked up promptly
                        // if a reschedule doesn't cancel this task first.
                        let idleSleepStart = now()
                        try await sleepForSeconds(Self.idleSleepSeconds)

                        // Detect system sleep/wake: if wall clock advanced far beyond 30s,
                        // the system likely slept. Process any due alerts immediately
                        // instead of looping back to re-check.
                        let idleDrift = now().timeIntervalSince(idleSleepStart)
                            - Self.idleSleepSeconds
                        if idleDrift > Self.wakeDriftThreshold {
                            logger.info(
                                "WAKE DETECTED: Idle sleep overran by \(String(format: "%.1f", idleDrift))s — processing due alerts",
                            )
                            guard !Task.isCancelled else { break }
                            checkForTriggeredAlerts(overlayManager: overlayManager)
                        }
                        continue
                    }

                    let currentTime = now()
                    let timeUntilTrigger = nextAlert.triggerDate.timeIntervalSince(currentTime)

                    if timeUntilTrigger > Self.triggerThresholdSeconds {
                        logger
                            .debug(
                                "MONITORING: Sleeping for \(String(format: "%.2f", timeUntilTrigger))s until next alert for event \(nextAlert.event.id)",
                            )
                        let sleepStart = now()
                        // Sleep exactly until the next alert (plus a tiny buffer)
                        try await sleepForSeconds(timeUntilTrigger)

                        // Detect system sleep/wake: wall clock advanced far beyond expected
                        let sleepDrift = now().timeIntervalSince(sleepStart) - timeUntilTrigger
                        if sleepDrift > Self.wakeDriftThreshold {
                            logger.info(
                                "WAKE DETECTED: Alert sleep overran by \(String(format: "%.1f", sleepDrift))s — processing all due alerts",
                            )
                        }
                    }

                    // Double check cancellation before processing
                    guard !Task.isCancelled else { break }

                    // Process triggers
                    checkForTriggeredAlerts(overlayManager: overlayManager)
                } catch {
                    // Task cancellation throws cancellation error
                    if Task.isCancelled {
                        break
                    }
                    logger.error("Alert monitoring error: \(error.localizedDescription)")
                    // Prevent rapid error looping
                    try? await sleepForSeconds(Self.errorRecoverySleepSeconds)
                }
            }
        }
    }

    /// Restarts the monitoring task to pick up new alerts immediately.
    /// No-op if monitoring was not explicitly started (e.g. tests using
    /// `scheduleWithoutMonitoring` to avoid TestClock starvation).
    private func refreshMonitoring() {
        guard monitoringEnabled, let overlayManager = currentOverlayManager else { return }
        logger.debug("MONITORING: Refreshing monitor task")
        startMonitoring(overlayManager: overlayManager)
    }

    private func checkForTriggeredAlerts(overlayManager: any OverlayManaging) {
        let currentTime = now()

        // Find alerts that should trigger
        let triggeredAlerts = scheduledAlerts.filter { alert in
            alert.triggerDate <= currentTime
        }

        if !triggeredAlerts.isEmpty {
            logger.debug("Found \(triggeredAlerts.count) triggered alerts at \(currentTime)")
            for alert in triggeredAlerts {
                let alertTypeName = switch alert.alertType {
                case let .reminder(minutes):
                    "reminder(\(minutes)min)"
                case let .snooze(until):
                    "snooze(until: \(until))"
                case .meetingStart:
                    "meetingStart"
                }
                logger.debug(
                    "  - \(alertTypeName) for event \(alert.event.id) (trigger: \(alert.triggerDate))",
                )
            }
        }

        for alert in triggeredAlerts {
            handleTriggeredAlert(alert, overlayManager: overlayManager)
        }

        // Remove triggered alerts
        let beforeCount = scheduledAlerts.count
        scheduledAlerts.removeAll { alert in
            triggeredAlerts.contains { $0.id == alert.id }
        }

        if !triggeredAlerts.isEmpty {
            let afterCount = scheduledAlerts.count
            logger.debug(
                "Processed \(triggeredAlerts.count) alerts, \(afterCount) remaining (was \(beforeCount))",
            )
        }
    }

    /// Resolves the effective alert mode for an event based on its calendar's setting.
    /// Defaults to `.overlay` when no mode is configured for the calendar.
    private func resolveAlertMode(for event: Event) -> AlertMode {
        calendarAlertModes[event.calendarId] ?? .overlay
    }

    /// Routes an alert through the appropriate delivery channel based on the
    /// event's calendar alert mode. Snooze alerts always use overlay.
    private func handleTriggeredAlert(_ alert: ScheduledAlert, overlayManager: any OverlayManaging) {
        let alertTypeName: String
        switch alert.alertType {
        case let .reminder(minutes):
            alertTypeName = "reminder(\(minutes)min)"
            deliverAlert(for: alert.event, overlayManager: overlayManager, fromSnooze: false)

        case .meetingStart:
            alertTypeName = "meetingStart"
            if preferencesManager.autoJoinEnabled, let url = linkParser.primaryLink(for: alert.event) {
                logger.info("AUTO-JOIN: Opening meeting for event \(alert.event.id)")
                NSWorkspace.shared.open(url)
            }

        case let .snooze(until):
            alertTypeName = "snooze(until:\(until))"
            // Snooze always uses overlay — user explicitly asked to be reminded.
            logger.info("SNOOZE: Re-showing overlay for event \(alert.event.id)")
            overlayManager.showOverlay(for: alert.event, fromSnooze: true)
        }

        AppDiagnostics.record(component: "EventScheduler", phase: "alertTriggered") {
            [
                "eventId": PrivacyUtils.redactedEventId(alert.event.id),
                "type": alertTypeName,
                "title": PrivacyUtils.redactedTitle(alert.event.title),
            ]
        }
    }

    /// Delivers an alert via overlay or notification based on the calendar's alert mode.
    private func deliverAlert(
        for event: Event,
        overlayManager: any OverlayManaging,
        fromSnooze: Bool,
    ) {
        let mode = resolveAlertMode(for: event)
        switch mode {
        case .overlay:
            logger.info("REMINDER: Showing overlay for event \(event.id)")
            overlayManager.showOverlay(for: event, fromSnooze: fromSnooze)

        case .notification:
            logger.info("REMINDER: Sending notification for event \(event.id)")
            let primaryLink = linkParser.primaryLink(for: event)
            guard let notificationManager else {
                logger.error("NotificationManager unavailable — cannot deliver alert for event \(event.id)")
                AppDiagnostics.record(
                    component: "EventScheduler",
                    phase: "deliverAlert",
                    outcome: .failure,
                ) {
                    [
                        "eventId": PrivacyUtils.redactedEventId(event.id),
                        "reason": "notificationManagerUnavailable",
                    ]
                }
                return
            }
            Task {
                await notificationManager.sendMeetingNotification(for: event, primaryLink: primaryLink)
            }

        case .none:
            logger.info("REMINDER: Suppressed for event \(event.id) (alert mode = none)")
        }

        AppDiagnostics.record(component: "EventScheduler", phase: "deliverAlert") {
            [
                "eventId": PrivacyUtils.redactedEventId(event.id),
                "mode": mode.rawValue,
                "fromSnooze": "\(fromSnooze)",
            ]
        }
    }

    func scheduleSnooze(for event: Event, minutes: Int) {
        let snoozeDate = now().addingTimeInterval(
            TimeInterval(minutes) * Self.secondsPerMinute,
        )
        // Allow snoozing past meeting start — user might want to join late.
        let snoozeAlert = ScheduledAlert(
            event: event,
            triggerDate: snoozeDate,
            alertType: .snooze(until: snoozeDate),
        )

        scheduledAlerts.append(snoozeAlert)
        scheduledAlerts.sort { $0.triggerDate < $1.triggerDate }

        let status = event.startDate < now() ? "already started" : "starts later"
        logger.info(
            "Scheduled snooze for \(minutes)min for event \(event.id) (\(status)). Trigger: \(snoozeDate)",
        )

        // Restart monitoring to pick up this snooze if it's next.
        refreshMonitoring()
    }
}
