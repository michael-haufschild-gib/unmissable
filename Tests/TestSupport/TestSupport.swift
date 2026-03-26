import AppKit
import Foundation
import OSLog
@testable import Unmissable

// MARK: - Test-Safe Implementations

/// Test-safe overlay manager that doesn't create actual UI elements
@MainActor
public final class TestSafeOverlayManager: OverlayManaging {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "TestSupport")

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
    private let logger = Logger(subsystem: "com.unmissable.app", category: "TestSupport")

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
