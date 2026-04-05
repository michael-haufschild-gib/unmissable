import AppKit
import Foundation
import Magnet
import Observation
import OSLog
import Sauce

@Observable
final class ShortcutsManager {
    private let logger = Logger(category: "ShortcutsManager")

    // MARK: - Display Constants

    /// Human-readable shortcut labels for the preferences UI.
    /// Keep in sync with the KeyCombo definitions in setupDefaultShortcuts().
    static let dismissShortcutDisplay = "⌘⎋"
    static let joinShortcutDisplay = "⌘⏎"

    private(set) var dismissShortcut: HotKey?
    private(set) var joinShortcut: HotKey?

    private weak var overlayManager: (any OverlayManaging)?
    private let linkParser: LinkParser

    init(overlayManager: (any OverlayManaging)? = nil, linkParser: LinkParser) {
        self.overlayManager = overlayManager
        self.linkParser = linkParser
        if overlayManager != nil {
            setupDefaultShortcuts()
        }
    }

    func setup(overlayManager: any OverlayManaging) {
        self.overlayManager = overlayManager
        setupDefaultShortcuts()
    }

    private func setupDefaultShortcuts() {
        dismissShortcut = registerHotKey(
            identifier: "dismiss_overlay",
            key: .escape,
            modifiers: .command,
            label: "Cmd+Escape",
        ) { [weak self] in self?.dismissOverlay() }

        joinShortcut = registerHotKey(
            identifier: "join_meeting",
            key: .return,
            modifiers: .command,
            label: "Cmd+Return",
        ) { [weak self] in self?.joinMeeting() }
    }

    private func registerHotKey(
        identifier: String,
        key: Key,
        modifiers: NSEvent.ModifierFlags,
        label: String,
        action: @escaping @MainActor () -> Void,
    ) -> HotKey? {
        guard let keyCombo = KeyCombo(key: key, cocoaModifiers: modifiers) else {
            logger.error("Failed to create key combination for \(identifier)")
            return nil
        }

        let hotKey = HotKey(identifier: identifier, keyCombo: keyCombo) { _ in
            Task { @MainActor in action() }
        }

        guard hotKey.register() else {
            logger.error("Failed to register \(identifier) — key combo may already be in use")
            return nil
        }

        logger.info("Registered shortcut \(identifier): \(label)")
        return hotKey
    }

    func dismissOverlay() {
        guard let overlayManager, overlayManager.isOverlayVisible else {
            logger.info("Dismiss shortcut pressed but no overlay is visible")
            return
        }

        logger.info("Dismissing overlay via global shortcut")
        overlayManager.hideOverlay()
    }

    func joinMeeting() {
        guard let overlayManager,
              overlayManager.isOverlayVisible,
              let event = overlayManager.activeEvent,
              let url = linkParser.primaryLink(for: event)
        else {
            logger.info("Join shortcut pressed but no active meeting to join")
            return
        }

        logger.info("Joining meeting via global shortcut: \(PrivacyUtils.redactedTitle(event.title))")
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
