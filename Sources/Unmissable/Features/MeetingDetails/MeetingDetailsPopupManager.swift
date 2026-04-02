import AppKit
import OSLog
import SwiftUI

/// Default size for the meeting details popup window.
/// Shared between MeetingDetailsView and MeetingDetailsPopupManager.
enum MeetingDetailsLayout {
    static let popupSize = NSSize(width: 480, height: 600)
}

@MainActor
final class MeetingDetailsPopupManager: MeetingDetailsPopupManaging {
    private let logger = Logger(category: "MeetingDetailsPopupManager")

    @Published
    private(set) var isPopupVisible = false
    private var popupWindow: NSWindow?
    private var currentEventId: String?
    private weak var parentWindow: NSWindow?
    // Intentionally strong: sole owner of the delegate (NSWindow.delegate is weak)
    // swiftlint:disable:next weak_delegate
    private var windowDelegate: PopupWindowDelegate?
    private let themeManager: ThemeManager

    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
    }

    // MARK: - Popup Management

    func showPopup(for event: Event, relativeTo parentWindow: NSWindow? = nil) {
        logger.info("POPUP: Showing details for event \(event.id)")

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

        // Create popup window
        let popup = createPopupWindow(for: event, relativeTo: parentWindow)
        popupWindow = popup
        currentEventId = event.id
        isPopupVisible = true

        popup.makeKeyAndOrderFront(nil)

        logger.info("POPUP: Displayed popup for event \(event.id)")
    }

    func hidePopup() {
        guard let popup = popupWindow else { return }

        logger.info("POPUP: Hiding popup")

        // CRITICAL: Use orderOut instead of close to prevent deadlocks
        popup.orderOut(nil)

        // Clean up state
        popupWindow = nil
        currentEventId = nil
        windowDelegate = nil
        isPopupVisible = false
        parentWindow = nil

        logger.info("POPUP: Successfully hidden popup")
    }

    // MARK: - Private Methods

    private func createPopupWindow(for event: Event, relativeTo parentWindow: NSWindow?) -> NSWindow {
        // Create the SwiftUI content view
        // Note: No .onDisappear cleanup here — hidePopup() handles all state cleanup.
        // Adding redundant cleanup in onDisappear races with hidePopup() via the window delegate.
        let contentView = MeetingDetailsView(event: event, onClose: { [weak self] in self?.hidePopup() })
            .customThemedEnvironment(themeManager: themeManager)

        // Create NSWindow with borderless style for clean popup appearance
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: MeetingDetailsLayout.popupSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Configure window properties
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.level = NSWindow
            .Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1) // Above menu bar dropdowns
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
            let x = parentFrame.maxX + 10
            let y = parentFrame.midY - (windowSize.height / 2)

            // Ensure window stays on screen
            if let screen = parent.screen {
                let screenFrame = screen.visibleFrame
                let adjustedX = min(x, screenFrame.maxX - windowSize.width - 10)
                let adjustedY = max(
                    screenFrame.minY + 10, min(y, screenFrame.maxY - windowSize.height - 10)
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
