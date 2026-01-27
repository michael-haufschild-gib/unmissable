import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI

@MainActor
final class OverlayManager: ObservableObject, OverlayManaging {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "OverlayManager")

    @Published var activeEvent: Event?
    @Published var isOverlayVisible = false
    /// Error message if snooze fails due to scheduler unavailability
    @Published var snoozeError: String?

    /// Computed time until meeting starts (negative if meeting has started)
    /// Note: This is a computed property - the View manages its own timer for UI updates
    var timeUntilMeeting: TimeInterval {
        activeEvent?.startDate.timeIntervalSinceNow ?? 0
    }

    private var overlayWindows: [NSWindow] = []
    private var snoozeTask: Task<Void, Never>?
    private let preferencesManager: PreferencesManager
    private let soundManager: SoundManager
    private let focusModeManager: FocusModeManager

    /// SNOOZE FIX: Track when overlay is shown from snooze alert
    private var isSnoozedAlert = false

    /// Test mode to prevent UI creation in tests
    private let isTestMode: Bool

    /// Reference to EventScheduler for proper snooze scheduling
    /// Note: Weak reference requires validation before use
    private weak var eventScheduler: EventScheduler?

    init(
        preferencesManager: PreferencesManager, focusModeManager: FocusModeManager? = nil,
        isTestMode: Bool = false
    ) {
        self.preferencesManager = preferencesManager
        soundManager = SoundManager(preferencesManager: preferencesManager)
        self.focusModeManager =
            focusModeManager ?? FocusModeManager(preferencesManager: preferencesManager)
        // Auto-detect XCTest environment to avoid creating real windows during tests
        let isRunningUnderXCTest =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isTestMode = isTestMode || isRunningUnderXCTest
    }

    convenience init() {
        let prefs = PreferencesManager()
        self.init(
            preferencesManager: prefs, focusModeManager: FocusModeManager(preferencesManager: prefs),
            isTestMode: false
        )
    }

    func setEventScheduler(_ scheduler: EventScheduler) {
        eventScheduler = scheduler
    }

    func showOverlay(for event: Event, minutesBeforeMeeting _: Int = 5, fromSnooze: Bool = false) {
        let startTime = Date()
        logger.info("🎬 SHOW OVERLAY: Starting for event: \(event.title), fromSnooze: \(fromSnooze)")

        // Prevent overlapping overlay operations
        if isOverlayVisible, activeEvent?.id == event.id {
            logger.info("⚠️ SKIP: Overlay already visible for this event")
            return
        }

        // Check if we should show overlay based on Focus/DND status
        guard focusModeManager.shouldShowOverlay() else {
            logger.info("📵 FOCUS MODE: Overlay suppressed due to Focus/DND mode")
            return
        }

        // Clean up any existing overlay first (atomic operation)
        hideOverlay()

        // Track if this overlay is from a snooze alert
        isSnoozedAlert = fromSnooze

        // Set state atomically to prevent race conditions
        activeEvent = event
        isOverlayVisible = true
        snoozeError = nil // Clear any previous snooze error

        logger.info(
            "✅ OVERLAY STATE: Set isOverlayVisible = true for \(event.title), isSnoozed = \(isSnoozedAlert)"
        )

        // Play alert sound if enabled and allowed by focus mode
        if focusModeManager.shouldPlaySound() {
            soundManager.playAlertSound()
        }

        // Create windows synchronously (View manages its own countdown timer)
        createOverlayWindows(for: event)

        // Log successful overlay creation
        let responseTime = Date().timeIntervalSince(startTime)
        ProductionMonitor.shared.logOverlaySuccess(responseTime: responseTime)

        logger.info("🎬 SHOW OVERLAY: Completed for event: \(event.title) in \(responseTime)s")
    }

    func hideOverlay() {
        logger.info("🛑 HIDE OVERLAY: Starting cleanup")

        // Clean up scheduled timers and stop sound
        invalidateAllScheduledTimers()
        soundManager.stopSound()

        // Clear state immediately to prevent any race conditions
        activeEvent = nil
        isOverlayVisible = false
        isSnoozedAlert = false // Reset snooze flag
        snoozeError = nil

        // Close windows on background queue to avoid Window Server deadlock
        // This is the one place where we intentionally detach, as Window Server operations can be slow
        let windowsToClose = overlayWindows
        overlayWindows.removeAll()

        if !windowsToClose.isEmpty {
            logger.info("🪟 Hiding \(windowsToClose.count) overlay windows...")

            // Use orderOut instead of close to avoid Window Server deadlock
            // orderOut removes window from screen without complex cleanup that can deadlock
            for window in windowsToClose {
                window.orderOut(nil)
            }
        }

        logger.info("✅ HIDE OVERLAY: Cleanup completed")
    }

    func snoozeOverlay(for minutes: Int) {
        guard let event = activeEvent else {
            logger.warning("⚠️ SNOOZE: No active event to snooze")
            return
        }

        logger.info("Snoozing overlay for \(minutes) minutes")

        // Capture event before hiding overlay (which clears activeEvent)
        let eventToSnooze = event
        hideOverlay()

        // Use EventScheduler for proper snooze scheduling
        if let scheduler = eventScheduler {
            scheduler.scheduleSnooze(for: eventToSnooze, minutes: minutes)
            logger.info("✅ Snooze scheduled through EventScheduler")
        } else {
            // Fallback to Task-based method if EventScheduler not available
            logger.warning("⚠️ EventScheduler not available, using fallback Task-based snooze")

            snoozeTask = Task { @MainActor in
                do {
                    let snoozeSeconds = TimeInterval(minutes * 60)
                    logger.info("⏰ SNOOZE: Starting \(snoozeSeconds)s delay")
                    try await Task.sleep(for: .seconds(snoozeSeconds))

                    if !Task.isCancelled {
                        logger.info("⏰ SNOOZE: Delay complete, showing overlay")
                        showOverlay(for: eventToSnooze, minutesBeforeMeeting: 2, fromSnooze: true)
                    }
                } catch is CancellationError {
                    logger.info("⏰ SNOOZE: Task cancelled")
                } catch {
                    logger.error("⏰ SNOOZE: Unexpected error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func createOverlayWindows(for event: Event) {
        if isTestMode {
            logger.debug("🧪 TEST MODE: Skipping actual window creation for \(event.title)")
            return
        }

        let screens = NSScreen.screens

        // Use preferences to determine which displays to show on
        let screensToUse =
            preferencesManager.showOnAllDisplays ? screens : [NSScreen.main].compactMap { $0 }

        for screen in screensToUse {
            let window = createOverlayWindow(for: screen, event: event)
            overlayWindows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        // Force app activation to ensure windows receive input immediately
        // Since this is an LSUIElement (menu bar) app, windows don't steal focus automatically
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func createOverlayWindow(for screen: NSScreen, event: Event) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.backgroundColor = NSColor.black.withAlphaComponent(preferencesManager.overlayOpacity)
        window.isOpaque = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Button callbacks run on MainActor since OverlayManager is @MainActor
        let overlayContent = OverlayContentView(
            event: event,
            onDismiss: { [weak self] in
                // Simple Task to break out of button action context, already on MainActor
                Task { @MainActor in
                    self?.hideOverlay()
                }
            },
            onJoin: { [weak self] in
                Task { @MainActor in
                    if let url = event.primaryLink {
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
            isFromSnooze: isSnoozedAlert
        )
        .environmentObject(preferencesManager)
        // FIXED: Retain cycle resolved by moving timer to OverlayContentView

        let hostingView = NSHostingView(rootView: overlayContent)
        window.contentView = hostingView

        return window
    }

    // MARK: - Timer Cleanup

    private func invalidateAllScheduledTimers() {
        logger.info("🧹 CLEANUP: Stopping all scheduled tasks")

        // Cancel snooze task
        if let snoozeTask {
            snoozeTask.cancel()
            self.snoozeTask = nil
            logger.debug("🧹 CLEANUP: Cancelled snooze task")
        }
    }
}
