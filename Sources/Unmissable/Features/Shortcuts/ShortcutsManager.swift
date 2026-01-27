import AppKit
import Foundation
import Magnet
import OSLog

@MainActor
final class ShortcutsManager: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "ShortcutsManager")

    @Published var dismissShortcut: HotKey?
    @Published var joinShortcut: HotKey?

    private weak var overlayManager: OverlayManager?

    func setup(overlayManager: OverlayManager) {
        self.overlayManager = overlayManager
        setupDefaultShortcuts()
    }

    private func setupDefaultShortcuts() {
        // Dismiss overlay: Cmd+Escape
        setupDismissShortcut()

        // Join meeting: Cmd+Return
        setupJoinShortcut()
    }

    private func setupDismissShortcut() {
        guard let keyCombo = KeyCombo(key: .escape, cocoaModifiers: .command) else {
            logger.error("Failed to create dismiss shortcut key combination")
            return
        }

        dismissShortcut = HotKey(identifier: "dismiss_overlay", keyCombo: keyCombo) { _ in
            Task { @MainActor in
                self.dismissOverlay()
            }
        }

        dismissShortcut?.register()
        logger.info("Registered dismiss shortcut: Cmd+Escape")
    }

    private func setupJoinShortcut() {
        guard let keyCombo = KeyCombo(key: .return, cocoaModifiers: .command) else {
            logger.error("Failed to create join shortcut key combination")
            return
        }

        joinShortcut = HotKey(identifier: "join_meeting", keyCombo: keyCombo) { _ in
            Task { @MainActor in
                self.joinMeeting()
            }
        }

        joinShortcut?.register()
        logger.info("Registered join shortcut: Cmd+Return")
    }

    private func dismissOverlay() {
        guard overlayManager?.isOverlayVisible == true else {
            logger.info("Dismiss shortcut pressed but no overlay is visible")
            return
        }

        logger.info("Dismissing overlay via global shortcut")
        overlayManager?.hideOverlay()
    }

    private func joinMeeting() {
        guard let overlayManager,
              overlayManager.isOverlayVisible,
              let event = overlayManager.activeEvent,
              let url = event.primaryLink
        else {
            logger.info("Join shortcut pressed but no active meeting to join")
            return
        }

        logger.info("Joining meeting via global shortcut: \(event.title)")
        NSWorkspace.shared.open(url)
        overlayManager.hideOverlay()
    }

    func unregisterShortcuts() {
        dismissShortcut?.unregister()
        joinShortcut?.unregister()
        dismissShortcut = nil
        joinShortcut = nil
        logger.info("Unregistered all global shortcuts")
    }
}
