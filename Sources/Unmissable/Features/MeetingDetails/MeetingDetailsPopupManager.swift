import AppKit
import Observation
import OSLog
import SwiftUI

/// Default size for the meeting details popup window.
/// Shared between MeetingDetailsView and MeetingDetailsPopupManager.
enum MeetingDetailsLayout {
    private static let popupWidth: CGFloat = 480
    private static let popupHeight: CGFloat = 600
    static let popupSize = NSSize(width: popupWidth, height: popupHeight)
}

@Observable
final class MeetingDetailsPopupManager: MeetingDetailsPopupManaging {
    private let logger = Logger(category: "MeetingDetailsPopupManager")

    private(set) var isPopupVisible = false
    private(set) var lastShownEvent: Event?
    private var popupWindow: NSWindow?
    private var currentEventId: String?
    private weak var parentWindow: NSWindow?
    // Intentionally strong: sole owner of the delegate (NSWindow.delegate is weak)
    // swiftlint:disable:next weak_delegate
    private var windowDelegate: PopupWindowDelegate?
    private var alertOverrideTask: Task<Void, Never>?
    private let themeManager: ThemeManager
    private let databaseManager: any DatabaseManaging

    private static let windowSpacing: CGFloat = 10
    private static let windowLevelOffset = 1
    private static let windowCenterDivisor: CGFloat = 2

    init(themeManager: ThemeManager, databaseManager: any DatabaseManaging) {
        self.themeManager = themeManager
        self.databaseManager = databaseManager
    }

    // MARK: - Popup Management

    func showPopup(for event: Event, relativeTo parentWindow: NSWindow? = nil) {
        logger.info("POPUP: Showing details for event \(PrivacyUtils.redactedEventId(event.id))")

        // If already showing the same event, just bring to front
        if isPopupVisible, currentEventId == event.id, let currentWindow = popupWindow {
            logger.info("POPUP: Same event already visible, bringing to front")
            currentWindow.makeKeyAndOrderFront(nil)
            return
        }

        // Close any existing popup (may be a different event)
        hidePopup()

        // Store parent window reference
        self.parentWindow = parentWindow

        // Create popup window with nil override initially, then update asynchronously
        let popup = createPopupWindow(
            for: event,
            relativeTo: parentWindow,
            alertOverrideMinutes: nil,
        )
        popupWindow = popup
        currentEventId = event.id
        lastShownEvent = event
        isPopupVisible = true

        popup.makeKeyAndOrderFront(nil)

        // Fetch alert override and update popup content asynchronously
        alertOverrideTask?.cancel()
        alertOverrideTask = Task {
            let override = try? await databaseManager.fetchAlertOverride(
                for: event.id, calendarId: event.calendarId,
            )
            guard !Task.isCancelled,
                  override != nil,
                  isPopupVisible,
                  currentEventId == event.id
            else { return }
            let updatedView = MeetingDetailsView(
                event: event,
                onClose: { [weak self] in self?.hidePopup() },
                alertOverrideMinutes: override,
            )
            .themed(themeManager: themeManager)
            popup.contentView = NSHostingView(rootView: updatedView)
        }

        logger.info("POPUP: Displayed popup for event \(PrivacyUtils.redactedEventId(event.id))")
    }

    func hidePopup() {
        guard let popup = popupWindow else { return }

        logger.info("POPUP: Hiding popup")

        alertOverrideTask?.cancel()
        alertOverrideTask = nil

        // CRITICAL: Use orderOut instead of close to prevent deadlocks
        popup.orderOut(nil)

        // Clean up state
        popupWindow = nil
        currentEventId = nil
        lastShownEvent = nil
        windowDelegate = nil
        isPopupVisible = false
        parentWindow = nil

        logger.info("POPUP: Successfully hidden popup")
    }

    // MARK: - Private Methods

    private func createPopupWindow(
        for event: Event,
        relativeTo parentWindow: NSWindow?,
        alertOverrideMinutes: Int? = nil,
    ) -> NSWindow {
        // Create the SwiftUI content view
        // Note: No .onDisappear cleanup here — hidePopup() handles all state cleanup.
        // Adding redundant cleanup in onDisappear races with hidePopup() via the window delegate.
        let contentView = MeetingDetailsView(
            event: event,
            onClose: { [weak self] in self?.hidePopup() },
            alertOverrideMinutes: alertOverrideMinutes,
        )
        .themed(themeManager: themeManager)

        // Create NSWindow with borderless style for clean popup appearance
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: MeetingDetailsLayout.popupSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )

        // Configure window properties
        window.title = "Meeting Details"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.level = NSWindow
            .Level(
                rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + Self.windowLevelOffset,
            ) // Above menu bar dropdowns
        window.hidesOnDeactivate = false // FIXED: Don't hide when clicking elsewhere - let user manually close
        window.backgroundColor = .clear // Transparent background for clean appearance
        window.hasShadow = true // Add shadow for depth
        window.isOpaque = false // Allow for rounded corners
        window.isMovableByWindowBackground = true // Enable dragging by clicking anywhere in window

        // Position the window
        positionWindow(window, relativeTo: parentWindow)

        // Set up window delegate for cleanup — stored as property to prevent deallocation
        let delegate = PopupWindowDelegate { [weak self] in
            Task { @MainActor in
                self?.hidePopup()
            }
        }
        window.delegate = delegate
        self.windowDelegate = delegate

        return window
    }

    private func positionWindow(_ window: NSWindow, relativeTo parentWindow: NSWindow?) {
        if let parent = parentWindow {
            // Position relative to parent window (menu bar)
            let parentFrame = parent.frame
            let windowSize = window.frame.size

            // Position to the right of the parent with some spacing
            let x = parentFrame.maxX + Self.windowSpacing
            let y = parentFrame.midY - (windowSize.height / Self.windowCenterDivisor)

            // Ensure window stays on screen
            if let screen = parent.screen {
                let screenFrame = screen.visibleFrame
                let adjustedX = min(x, screenFrame.maxX - windowSize.width - Self.windowSpacing)
                let adjustedY = max(
                    screenFrame.minY + Self.windowSpacing,
                    min(y, screenFrame.maxY - windowSize.height - Self.windowSpacing),
                )

                window.setFrameOrigin(NSPoint(x: adjustedX, y: adjustedY))
            } else {
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        } else {
            // Center on screen if no parent
            window.center()
        }
    }
}

// MARK: - Window Delegate

private class PopupWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func windowWillClose(_: Notification) {
        onClose()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Close popup when it loses focus to another window, but not when a child
        // menu or context menu is active (those don't become key windows).
        guard let window = notification.object as? NSWindow else { return }

        // Defer to the next run loop iteration so the key window state is settled.
        // This replaces the previous Task.sleep race with a deterministic dispatch.
        DispatchQueue.main.async { [weak self] in
            // Don't close if the popup regained focus or no window is key
            // (a menu/popover is likely open above the popup)
            let keyWindow = NSApp.keyWindow
            if keyWindow === window || keyWindow == nil {
                return
            }
            self?.onClose()
        }
    }
}
