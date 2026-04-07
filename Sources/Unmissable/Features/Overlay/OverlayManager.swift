import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class OverlayManager: OverlayManaging {
    private let logger = Logger(category: "OverlayManager")

    var activeEvent: Event?
    var isOverlayVisible = false

    /// Computed time until meeting starts (negative if meeting has started)
    /// Note: This is a computed property - the View manages its own timer for UI updates
    var timeUntilMeeting: TimeInterval {
        activeEvent?.startDate.timeIntervalSinceNow ?? 0
    }

    private var overlayWindows: [NSWindow] = []

    @ObservationIgnored
    private nonisolated(unsafe) var screenParameterObserver: (any NSObjectProtocol)?

    private let preferencesManager: PreferencesManager
    private let soundManager: SoundManager
    private let foregroundAppDetector: any ForegroundAppDetecting
    private let notificationManager: any NotificationManaging
    private let linkParser: LinkParser
    private let themeManager: ThemeManager

    /// SNOOZE FIX: Track when overlay is shown from snooze alert
    private var isSnoozedAlert = false

    /// Test mode to prevent UI creation in tests
    private let isTestMode: Bool

    /// Required dependency for snooze scheduling — must be provided at init.
    private let eventScheduler: EventScheduler

    private static let normalMaxAgeMinutes = 5
    private static let snoozeMaxAgeMinutes = 30
    private static let secondsPerMinute = 60

    private static let normalMaxAgeSeconds = TimeInterval(normalMaxAgeMinutes * secondsPerMinute)
    private static let snoozeMaxAgeSeconds = TimeInterval(snoozeMaxAgeMinutes * secondsPerMinute)
    private static let millisecondsPerSecond = 1000

    init(
        preferencesManager: PreferencesManager,
        eventScheduler: EventScheduler,
        soundManager: SoundManager,
        foregroundAppDetector: any ForegroundAppDetecting = ForegroundAppDetector(),
        notificationManager: any NotificationManaging,
        linkParser: LinkParser = LinkParser(),
        themeManager: ThemeManager,
        isTestMode: Bool = false,
    ) {
        self.preferencesManager = preferencesManager
        self.eventScheduler = eventScheduler
        self.soundManager = soundManager
        self.foregroundAppDetector = foregroundAppDetector
        self.notificationManager = notificationManager
        self.linkParser = linkParser
        self.themeManager = themeManager
        self.isTestMode = isTestMode

        if !isTestMode {
            screenParameterObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleScreenParametersChanged()
                }
            }
        }
    }

    deinit {
        if let observer = screenParameterObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func showOverlay(for event: Event, fromSnooze: Bool = false) {
        let startTime = Date()
        logger.info(
            "SHOW OVERLAY: Starting for event \(PrivacyUtils.redactedEventId(event.id)), fromSnooze: \(fromSnooze)",
        )

        // Prevent overlapping overlay operations
        if isOverlayVisible, activeEvent?.id == event.id {
            logger.info("SKIP: Overlay already visible for this event")
            AppDiagnostics.record(
                component: "OverlayManager",
                phase: "showOverlay",
                outcome: .skipped,
            ) {
                ["eventId": PrivacyUtils.redactedEventId(event.id), "reason": "alreadyVisible"]
            }
            return
        }

        // Auto-dismiss for meetings that started too long ago
        let timeSinceStart = Date().timeIntervalSince(event.startDate)
        let maxAge: TimeInterval = fromSnooze ? Self.snoozeMaxAgeSeconds : Self.normalMaxAgeSeconds
        if timeSinceStart > maxAge {
            logger.info(
                "SKIP: Meeting \(PrivacyUtils.redactedEventId(event.id)) started \(Int(timeSinceStart) / Self.secondsPerMinute)min ago (max \(Int(maxAge) / Self.secondsPerMinute)min)",
            )
            AppDiagnostics.record(component: "OverlayManager", phase: "showOverlay", outcome: .skipped) {
                [
                    "eventId": PrivacyUtils.redactedEventId(event.id),
                    "reason": "tooOld",
                    "ageSec": "\(Int(timeSinceStart))",
                    "maxAgeSec": "\(Int(maxAge))",
                ]
            }
            return
        }

        // Smart suppression: skip overlay if meeting app is already in the foreground.
        // fromSnooze alerts are never suppressed — user explicitly requested a re-reminder.
        if !fromSnooze, preferencesManager.smartSuppression,
           let provider = event.provider
        {
            if foregroundAppDetector.isMeetingAppInForeground(for: provider) {
                logger.info(
                    "SMART SUPPRESS: Native app in foreground for \(PrivacyUtils.redactedEventId(event.id)) (\(provider.displayName))",
                )
                AppDiagnostics.record(component: "OverlayManager", phase: "showOverlay", outcome: .skipped) {
                    [
                        "eventId": PrivacyUtils.redactedEventId(event.id),
                        "reason": "smartSuppress.nativeApp",
                        "provider": provider.displayName,
                    ]
                }
                sendSuppressionFallback(for: event)
                return
            }
            if provider == .meet, foregroundAppDetector.isBrowserInForeground() {
                logger.info(
                    "SMART SUPPRESS: Browser in foreground for Meet event \(PrivacyUtils.redactedEventId(event.id))",
                )
                AppDiagnostics.record(component: "OverlayManager", phase: "showOverlay", outcome: .skipped) {
                    ["eventId": PrivacyUtils.redactedEventId(event.id), "reason": "smartSuppress.browser"]
                }
                sendSuppressionFallback(for: event)
                return
            }
        }

        // Clean up any existing overlay first (atomic operation)
        hideOverlay()

        // Track if this overlay is from a snooze alert
        isSnoozedAlert = fromSnooze

        // Set state atomically to prevent race conditions
        activeEvent = event
        isOverlayVisible = true

        logger.info(
            "OVERLAY STATE: Set isOverlayVisible = true for event \(PrivacyUtils.redactedEventId(event.id)), isSnoozed = \(self.isSnoozedAlert)",
        )

        // Play alert sound if enabled
        soundManager.playAlertSound()

        // Create windows synchronously (View manages its own countdown timer)
        createOverlayWindows(for: event)

        logShowOverlayCompletion(event: event, fromSnooze: fromSnooze, startTime: startTime)
    }

    private func logShowOverlayCompletion(event: Event, fromSnooze: Bool, startTime: Date) {
        let responseTime = Date().timeIntervalSince(startTime)
        logger.info("SHOW OVERLAY: Completed for event \(PrivacyUtils.redactedEventId(event.id)) in \(responseTime)s")
        AppDiagnostics.record(component: "OverlayManager", phase: "showOverlay") {
            [
                "eventId": PrivacyUtils.redactedEventId(event.id),
                "title": PrivacyUtils.redactedTitle(event.title),
                "fromSnooze": "\(fromSnooze)",
                "responseMs": "\(Int(responseTime * Double(Self.millisecondsPerSecond)))",
                "windowCount": "\(self.overlayWindows.count)",
            ]
        }
    }

    /// Sends a lightweight notification when the overlay is suppressed by smart suppression.
    /// Ensures the user still gets a reminder even when their meeting app is already in the foreground.
    private func sendSuppressionFallback(for event: Event) {
        let primaryLink = linkParser.primaryLink(for: event)
        Task {
            await notificationManager.sendMeetingNotification(for: event, primaryLink: primaryLink)
        }
        logger.info("SMART SUPPRESS: Sent fallback notification for \(PrivacyUtils.redactedEventId(event.id))")
    }

    func hideOverlay() {
        logger.info("HIDE OVERLAY: Starting cleanup")

        soundManager.stopSound()

        // Clear state immediately to prevent any race conditions
        activeEvent = nil
        isOverlayVisible = false
        isSnoozedAlert = false // Reset snooze flag

        // Capture and detach windows from the manager immediately so no further
        // operations reference them, then close on the next run-loop iteration.
        // Deferring via Task breaks re-entrancy when hideOverlay() is triggered
        // from a button action running inside the window's own view hierarchy —
        // close() would otherwise re-enter the responder chain and deadlock the
        // Window Server.
        let windowsToClose = overlayWindows
        overlayWindows.removeAll()

        if !windowsToClose.isEmpty {
            logger.info("Hiding \(windowsToClose.count) overlay windows...")

            Task { @MainActor in
                for window in windowsToClose {
                    window.close()
                }
            }
        }

        logger.info("HIDE OVERLAY: Cleanup completed")
    }

    func snoozeOverlay(for minutes: Int) {
        guard let event = activeEvent else {
            logger.warning("SNOOZE: No active event to snooze")
            return
        }

        logger.info("Snoozing overlay for \(minutes) minutes")

        // Capture event before hiding overlay (which clears activeEvent)
        let eventToSnooze = event
        hideOverlay()

        eventScheduler.scheduleSnooze(for: eventToSnooze, minutes: minutes)
        logger.info("Snooze scheduled through EventScheduler")
    }

    private func handleScreenParametersChanged() {
        guard isOverlayVisible, let event = activeEvent else { return }

        logger.info("Screen parameters changed — recreating \(self.overlayWindows.count) overlay windows")

        let staleWindows = overlayWindows
        overlayWindows.removeAll()
        for window in staleWindows {
            window.close()
        }

        createOverlayWindows(for: event)
    }

    private func createOverlayWindows(for event: Event) {
        if isTestMode {
            logger.debug(
                "TEST MODE: Skipping actual window creation for event \(PrivacyUtils.redactedEventId(event.id))",
            )
            return
        }

        let screens = NSScreen.screens

        // Use preferences to determine which displays to show on
        let screensToUse =
            preferencesManager.showOnAllDisplays ? screens : [NSScreen.main].compactMap(\.self)

        for screen in screensToUse {
            let window = createOverlayWindow(for: screen, event: event)
            overlayWindows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        // Force app activation to ensure windows receive input immediately
        // Since this is an LSUIElement (menu bar) app, windows don't steal focus automatically
        NSApplication.shared.activate()
    }

    private func createOverlayWindow(for screen: NSScreen, event: Event) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen,
        )

        window.isReleasedWhenClosed = false
        window.title = "Meeting Overlay"
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Button callbacks run on MainActor since OverlayManager is MainActor-isolated
        let linkParser = self.linkParser
        let overlayContent = OverlayContentView(
            event: event,
            linkParser: linkParser,
            onDismiss: { [weak self] in
                // Simple Task to break out of button action context, already on MainActor
                Task { @MainActor in
                    self?.hideOverlay()
                }
            },
            onJoin: { [weak self] in
                Task { @MainActor in
                    if let url = linkParser.primaryLink(for: event) {
                        NSWorkspace.shared.open(url)
                        self?.hideOverlay()
                    }
                }
            },
            onSnooze: { [weak self] minutes in
                Task { @MainActor in
                    self?.snoozeOverlay(for: minutes)
                }
            },
            isFromSnooze: isSnoozedAlert,
        )
        .environment(preferencesManager)
        .themed(themeManager: themeManager)

        let hostingView = NSHostingView(rootView: overlayContent)
        window.contentView = hostingView

        return window
    }
}
