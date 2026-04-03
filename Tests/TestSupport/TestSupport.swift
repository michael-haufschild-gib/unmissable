import AppKit
import Clocks
import ConcurrencyExtras
import Foundation
import OSLog
@testable import Unmissable

// MARK: - Controllable Test Clock

/// Bridges PointFree's `TestClock<Duration>` to EventScheduler's closure-based
/// `sleepForSeconds` / `now` interface.
///
/// PointFree's TestClock uses continuation-based suspension: `sleep` suspends
/// the caller until the test explicitly calls `advance(by:)`. This eliminates
/// MainActor starvation — the monitoring loop simply suspends and never spins.
///
/// Usage:
/// ```swift
/// let clock = TestClock()
/// let scheduler = EventScheduler(sleepForSeconds: clock.sleepForSeconds,
///                                 now: clock.nowProvider)
/// // ... trigger scheduling ...
/// await clock.advance(by: .seconds(600))  // fires alerts 10 min in the future
/// ```
@preconcurrency @MainActor
public final class TestClock {
    /// The underlying PointFree TestClock that handles continuation-based sleep.
    public let underlying = Clocks.TestClock<Duration>()

    /// Wall-clock anchor: the real Date at the moment this TestClock was created.
    /// Used to convert between Duration offsets and absolute Dates.
    private let anchorDate: Date

    /// Accumulated Duration offset from anchor. Updated whenever `advance` is called.
    private var elapsed: Duration = .zero

    private static let attosecondsPerSecond: Double = 1e18
    private static let millisecondsPerSecond: Double = 1000

    /// Creates a test clock anchored at the given time.
    public init(startTime: Date = Date()) {
        anchorDate = startTime
    }

    /// The simulated current time as a Date.
    public var currentTime: Date {
        anchorDate.addingTimeInterval(Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / Self.attosecondsPerSecond)
    }

    /// Closure suitable for `EventScheduler(sleepForSeconds:)`.
    /// Suspends via PointFree's TestClock — the caller blocks until
    /// `advance(by:)` is called from the test. No spinning, no starvation.
    public var sleepForSeconds: @Sendable (TimeInterval) async throws -> Void {
        { [weak underlying] seconds in
            guard let clock = underlying else { throw CancellationError() }
            try await clock.sleep(for: .milliseconds(Int(seconds * Self.millisecondsPerSecond)))
        }
    }

    /// Closure suitable for `EventScheduler(now:)`.
    public var nowProvider: @Sendable () -> Date {
        { [weak self] in
            guard let self else { return Date() }
            return MainActor.assumeIsolated { self.currentTime }
        }
    }

    /// Advance the clock by a Duration, releasing any suspended sleepers
    /// whose deadline falls within the advanced range.
    public func advance(by duration: Duration) async {
        elapsed += duration
        await underlying.advance(by: duration)
    }

    /// Advance by seconds (convenience).
    public func advance(bySeconds seconds: TimeInterval) async {
        await advance(by: .milliseconds(Int(seconds * Self.millisecondsPerSecond)))
    }

    /// Run all pending suspensions to completion.
    public func runToCompletion() async {
        await underlying.run()
    }
}

// MARK: - Test-Safe Implementations

/// Test-safe overlay manager that doesn't create actual UI elements
@preconcurrency @MainActor
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
        let snoozeMaxAgeSeconds: TimeInterval = 1800
        let normalMaxAgeSeconds: TimeInterval = 300
        let maxAge: TimeInterval = fromSnooze ? snoozeMaxAgeSeconds : normalMaxAgeSeconds
        if timeSinceStart > maxAge {
            logger
                .debug(
                    "TEST-SAFE: Skipping overlay — meeting started \(Int(timeSinceStart))s ago (max \(Int(maxAge))s)",
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

@preconcurrency @MainActor
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
