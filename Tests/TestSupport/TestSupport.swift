import AppKit
import Foundation
import OSLog
@testable import Unmissable

// MARK: - Controllable Test Clock

/// Provides deterministic `sleep` and `now` closures for EventScheduler tests.
/// Advance `currentTime` to simulate passage of time without real delays.
/// `sleep` is a no-op by default — it yields once to let other tasks run,
/// then returns immediately, making timer-dependent tests instant.
@MainActor
public final class TestClock {
    /// The simulated current time. Advance this to move time forward for the scheduler.
    public var currentTime: Date

    /// When true, `sleep` advances `currentTime` by the requested duration
    /// before returning. This makes the monitoring loop's drift detection
    /// see consistent elapsed time.
    public var autoAdvance: Bool

    /// Creates a test clock starting at the given time.
    /// - Parameters:
    ///   - startTime: Initial simulated time (defaults to now).
    ///   - autoAdvance: Whether `sleep` auto-advances `currentTime`.
    public init(
        startTime: Date = Date(),
        autoAdvance: Bool = true
    ) {
        currentTime = startTime
        self.autoAdvance = autoAdvance
    }

    /// Closure suitable for `EventScheduler(sleepForSeconds:)`.
    /// Yields once so the caller's Task can be cancelled, then returns.
    public var sleep: @Sendable (TimeInterval) async throws -> Void {
        { [weak self] seconds in
            // Yield to allow cancellation and other tasks to run
            try Task.checkCancellation()
            await Task.yield()
            try Task.checkCancellation()

            // Advance time on the main actor if autoAdvance is on
            if let self {
                await MainActor.run {
                    if self.autoAdvance {
                        self.currentTime = self.currentTime.addingTimeInterval(seconds)
                    }
                }
            }
        }
    }

    /// Closure suitable for `EventScheduler(now:)`.
    public var nowProvider: () -> Date {
        { [weak self] in
            // Safe to read from MainActor-isolated property via
            // the nonisolated(unsafe) slot in EventScheduler
            self?.currentTime ?? Date()
        }
    }

    /// Advance time by a specific interval without going through sleep.
    public func advance(by seconds: TimeInterval) {
        currentTime = currentTime.addingTimeInterval(seconds)
    }
}

// MARK: - Test-Safe Implementations

/// Test-safe overlay manager that doesn't create actual UI elements
@MainActor
public final class TestSafeOverlayManager: OverlayManaging {
    private let logger = Logger(category: "TestSupport")

    @Published
    public var activeEvent: Event?
    @Published
    public var isOverlayVisible = false

    /// Computed time until meeting starts (negative if meeting has started)
    public var timeUntilMeeting: TimeInterval {
        activeEvent?.startDate.timeIntervalSinceNow ?? 0
    }

    private weak var eventScheduler: EventScheduler?
    private let isTestEnvironment: Bool

    public init(isTestEnvironment: Bool = false) {
        self.isTestEnvironment = isTestEnvironment
    }

    public func showOverlay(for event: Event, fromSnooze: Bool = false) {
        logger.debug("TEST-SAFE SHOW: Overlay for \(event.title), fromSnooze: \(fromSnooze)")

        // Mirror production dedup: skip if same event is already showing
        if isOverlayVisible, activeEvent?.id == event.id {
            logger.debug("TEST-SAFE: Skipping — overlay already visible for event \(event.id)")
            return
        }

        // Auto-dismiss for meetings that started too long ago
        let timeSinceStart = Date().timeIntervalSince(event.startDate)
        let maxAge: TimeInterval = fromSnooze ? 30 * 60 : 5 * 60
        if timeSinceStart > maxAge {
            logger
                .debug(
                    "TEST-SAFE: Skipping overlay — meeting started \(Int(timeSinceStart))s ago (max \(Int(maxAge))s)"
                )
            activeEvent = nil
            isOverlayVisible = false
            return
        }

        activeEvent = event
        isOverlayVisible = true
        logger.debug("TEST-SAFE: Set overlay visible = true")
    }

    public func hideOverlay() {
        logger.debug("TEST-SAFE HIDE: Overlay")
        activeEvent = nil
        isOverlayVisible = false
    }

    public func snoozeOverlay(for minutes: Int) {
        guard let event = activeEvent else { return }
        logger.debug("TEST-SAFE SNOOZE: \(minutes) minutes for \(event.title)")
        hideOverlay()
        eventScheduler?.scheduleSnooze(for: event, minutes: minutes)
    }

    public func setEventScheduler(_ scheduler: EventScheduler) {
        eventScheduler = scheduler
    }
}

// MARK: - Test-Safe Meeting Details Popup

@MainActor
public final class TestSafeMeetingDetailsPopupManager: MeetingDetailsPopupManaging {
    private let logger = Logger(category: "TestSupport")

    @Published
    public private(set) var isPopupVisible = false
    public private(set) var lastShownEvent: Event?

    public init() {}

    public func showPopup(for event: Event, relativeTo _: NSWindow? = nil) {
        logger.debug("TEST-SAFE SHOW: Popup for \(event.title)")

        // Mirror real behavior: if already visible, just log
        if isPopupVisible {
            logger.debug("TEST-SAFE: Popup already visible")
            return
        }

        lastShownEvent = event
        isPopupVisible = true
    }

    public func hidePopup() {
        logger.debug("TEST-SAFE HIDE: Popup")
        lastShownEvent = nil
        isPopupVisible = false
    }
}
