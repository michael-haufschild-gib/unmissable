import AppKit
import OSLog
import SwiftUI

@MainActor
final class MeetingDetailsPopupManager: ObservableObject {
  private let logger = Logger(
    subsystem: "com.unmissable.app", category: "MeetingDetailsPopupManager")

  @Published private(set) var isPopupVisible = false
  private var popupWindow: NSWindow?
  private weak var parentWindow: NSWindow?

  // MARK: - Popup Management

  func showPopup(for event: Event, relativeTo parentWindow: NSWindow? = nil) {
    logger.info("📋 POPUP: Showing details for event '\(event.title)'")

    // Prevent multiple popups for the same event
    if isPopupVisible, let currentWindow = popupWindow {
      logger.info("📋 POPUP: Popup already visible, bringing to front")
      currentWindow.makeKeyAndOrderFront(nil)
      return
    }

    // Hide any existing popup first
    hidePopup()

    // Store parent window reference
    self.parentWindow = parentWindow

    // Create popup window
    let popup = createPopupWindow(for: event, relativeTo: parentWindow)
    popupWindow = popup
    isPopupVisible = true

    // Show the popup
    popup.makeKeyAndOrderFront(nil)

    // DEBUG: Log window details
    let windowFrame = popup.frame
    logger.info(
      "📋 POPUP DEBUG: Window frame: x=\(windowFrame.origin.x), y=\(windowFrame.origin.y), w=\(windowFrame.size.width), h=\(windowFrame.size.height)"
    )
    logger.info("📋 POPUP DEBUG: Window level: \(popup.level.rawValue)")
    logger.info("📋 POPUP DEBUG: Window visible: \(popup.isVisible)")
    logger.info("📋 POPUP DEBUG: Window on active space: \(popup.isOnActiveSpace)")
    logger.info("📋 POPUP DEBUG: Content view exists: \(popup.contentView != nil)")

    logger.info("📋 POPUP: Successfully displayed popup for event '\(event.title)'")
  }

  func hidePopup() {
    guard let popup = popupWindow else { return }

    logger.info("📋 POPUP: Hiding popup")

    // CRITICAL: Use orderOut instead of close to prevent deadlocks
    popup.orderOut(nil)

    // Clean up state
    popupWindow = nil
    isPopupVisible = false
    parentWindow = nil

    logger.info("📋 POPUP: Successfully hidden popup")
  }

  // MARK: - Private Methods

  private func createPopupWindow(for event: Event, relativeTo parentWindow: NSWindow?) -> NSWindow {
    // Create the SwiftUI content view
    let contentView = MeetingDetailsView(event: event)
      .customThemedEnvironment()
      .onDisappear {
        // Clean up when view disappears
        Task { @MainActor in
          self.isPopupVisible = false
          self.popupWindow = nil
          self.parentWindow = nil
        }
      }

    // Create NSWindow with borderless style for clean popup appearance
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    // Configure window properties
    window.contentView = NSHostingView(rootView: contentView)
    window.isReleasedWhenClosed = false
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)  // Above menu bar dropdowns
    window.hidesOnDeactivate = false  // FIXED: Don't hide when clicking elsewhere - let user manually close
    window.backgroundColor = .clear  // Transparent background for clean appearance
    window.hasShadow = true  // Add shadow for depth
    window.isOpaque = false  // Allow for rounded corners
    window.isMovableByWindowBackground = true  // Enable dragging by clicking anywhere in window

    // Position the window
    positionWindow(window, relativeTo: parentWindow)

    // Set up window delegate for cleanup
    let delegate = PopupWindowDelegate { [weak self] in
      Task { @MainActor in
        self?.hidePopup()
      }
    }
    window.delegate = delegate

    // Store delegate to prevent deallocation
    withUnsafePointer(to: &AssociatedKeys.windowDelegate) { pointer in
      objc_setAssociatedObject(
        window,
        pointer,
        delegate,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
      )
    }

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
          screenFrame.minY + 10, min(y, screenFrame.maxY - windowSize.height - 10))

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

  func windowWillClose(_ notification: Notification) {
    onClose()
  }

  func windowDidResignKey(_ notification: Notification) {
    // Close popup when it loses focus to another window (but allow for brief interactions)
    Task {
      try? await Task.sleep(for: .milliseconds(100))
      await MainActor.run {
        self.onClose()
      }
    }
  }
}

// MARK: - Associated Object Keys

private enum AssociatedKeys {
  nonisolated(unsafe) static var windowDelegate: UInt8 = 0
}
