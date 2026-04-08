import AppKit
import Foundation
import Magnet
import Observation
import OSLog
import Sauce

@MainActor
@Observable
final class ShortcutsManager {
    private let logger = Logger(category: "ShortcutsManager")

    // MARK: - Default Key Combos

    static let defaultDismissKey: Key = .escape
    static let defaultDismissModifiers: NSEvent.ModifierFlags = .command
    static let defaultJoinKey: Key = .return
    static let defaultJoinModifiers: NSEvent.ModifierFlags = .command

    // MARK: - State

    private(set) var dismissShortcut: HotKey?
    private(set) var joinShortcut: HotKey?

    /// Human-readable keycap labels for the current dismiss shortcut.
    private(set) var dismissLabels: [String] = modifierAndKeyLabels(
        modifiers: defaultDismissModifiers, key: defaultDismissKey,
    )

    /// Human-readable keycap labels for the current join shortcut.
    private(set) var joinLabels: [String] = modifierAndKeyLabels(
        modifiers: defaultJoinModifiers, key: defaultJoinKey,
    )

    private weak var overlayManager: (any OverlayManaging)?
    private let linkParser: LinkParser

    @ObservationIgnored
    private weak var preferencesManager: PreferencesManager?

    init(overlayManager: (any OverlayManaging)? = nil, linkParser: LinkParser) {
        self.overlayManager = overlayManager
        self.linkParser = linkParser
        if overlayManager != nil {
            setupShortcuts()
        }
    }

    func setup(overlayManager: any OverlayManaging) {
        self.overlayManager = overlayManager
        setupShortcuts()
    }

    /// Connects the preferences manager for persistence. Call after init.
    func setPreferencesManager(_ manager: PreferencesManager) {
        self.preferencesManager = manager
        // Re-register using any persisted custom combos
        reloadFromPreferences()
    }

    // MARK: - Dynamic Registration

    /// Reloads shortcuts from persisted preferences, falling back to defaults.
    func reloadFromPreferences() {
        let dismissCombo = decodedKeyCombo(from: preferencesManager?.dismissShortcutJSON)
            ?? KeyCombo(key: Self.defaultDismissKey, cocoaModifiers: Self.defaultDismissModifiers)
        let joinCombo = decodedKeyCombo(from: preferencesManager?.joinShortcutJSON)
            ?? KeyCombo(key: Self.defaultJoinKey, cocoaModifiers: Self.defaultJoinModifiers)

        registerDismiss(keyCombo: dismissCombo)
        registerJoin(keyCombo: joinCombo)
    }

    /// Updates the dismiss shortcut to a new key combo. Returns `true` on success.
    @discardableResult
    func updateDismissShortcut(keyCombo: KeyCombo) -> Bool {
        guard registerDismiss(keyCombo: keyCombo) else { return false }
        preferencesManager?.setDismissShortcutJSON(encodedKeyCombo(keyCombo))
        return true
    }

    /// Updates the join shortcut to a new key combo. Returns `true` on success.
    @discardableResult
    func updateJoinShortcut(keyCombo: KeyCombo) -> Bool {
        guard registerJoin(keyCombo: keyCombo) else { return false }
        preferencesManager?.setJoinShortcutJSON(encodedKeyCombo(keyCombo))
        return true
    }

    /// Resets both shortcuts to defaults and clears persisted overrides.
    func resetToDefaults() {
        if let defaultDismiss = KeyCombo(key: Self.defaultDismissKey, cocoaModifiers: Self.defaultDismissModifiers) {
            registerDismiss(keyCombo: defaultDismiss)
        }
        if let defaultJoin = KeyCombo(key: Self.defaultJoinKey, cocoaModifiers: Self.defaultJoinModifiers) {
            registerJoin(keyCombo: defaultJoin)
        }
        preferencesManager?.setDismissShortcutJSON(nil)
        preferencesManager?.setJoinShortcutJSON(nil)
    }

    // MARK: - Registration

    @discardableResult
    private func registerDismiss(keyCombo: KeyCombo?) -> Bool {
        dismissShortcut?.unregister()
        dismissShortcut = nil

        guard let keyCombo else {
            dismissLabels = Self.modifierAndKeyLabels(
                modifiers: Self.defaultDismissModifiers, key: Self.defaultDismissKey,
            )
            overlayManager?.dismissShortcutHint = dismissHintText
            return true
        }

        let hotKey = HotKey(identifier: "dismiss_overlay", keyCombo: keyCombo) { [weak self] _ in
            Task { @MainActor in self?.dismissOverlay() }
        }

        guard hotKey.register() else {
            logger.error("Failed to register dismiss shortcut — key combo may already be in use")
            dismissLabels = Self.modifierAndKeyLabels(
                modifiers: Self.defaultDismissModifiers, key: Self.defaultDismissKey,
            )
            return false
        }

        dismissShortcut = hotKey
        dismissLabels = Self.modifierAndKeyLabels(
            modifiers: keyCombo.keyEquivalentModifierMask, key: keyCombo.key,
        )
        overlayManager?.dismissShortcutHint = dismissHintText
        logger.info("Registered dismiss shortcut: \(keyCombo.keyEquivalentModifierMaskString)\(keyCombo.characters)")
        return true
    }

    @discardableResult
    private func registerJoin(keyCombo: KeyCombo?) -> Bool {
        joinShortcut?.unregister()
        joinShortcut = nil

        guard let keyCombo else {
            joinLabels = Self.modifierAndKeyLabels(
                modifiers: Self.defaultJoinModifiers, key: Self.defaultJoinKey,
            )
            return true
        }

        let hotKey = HotKey(identifier: "join_meeting", keyCombo: keyCombo) { [weak self] _ in
            Task { @MainActor in self?.joinMeeting() }
        }

        guard hotKey.register() else {
            logger.error("Failed to register join shortcut — key combo may already be in use")
            joinLabels = Self.modifierAndKeyLabels(
                modifiers: Self.defaultJoinModifiers, key: Self.defaultJoinKey,
            )
            return false
        }

        joinShortcut = hotKey
        joinLabels = Self.modifierAndKeyLabels(
            modifiers: keyCombo.keyEquivalentModifierMask, key: keyCombo.key,
        )
        logger.info("Registered join shortcut: \(keyCombo.keyEquivalentModifierMaskString)\(keyCombo.characters)")
        return true
    }

    private func setupShortcuts() {
        let dismissCombo = decodedKeyCombo(from: preferencesManager?.dismissShortcutJSON)
            ?? KeyCombo(key: Self.defaultDismissKey, cocoaModifiers: Self.defaultDismissModifiers)
        let joinCombo = decodedKeyCombo(from: preferencesManager?.joinShortcutJSON)
            ?? KeyCombo(key: Self.defaultJoinKey, cocoaModifiers: Self.defaultJoinModifiers)

        registerDismiss(keyCombo: dismissCombo)
        registerJoin(keyCombo: joinCombo)
    }

    // MARK: - Actions

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

    /// Human-readable dismiss hint for the overlay, e.g. "Press ⌘ Esc to dismiss".
    var dismissHintText: String {
        "Press \(dismissLabels.joined(separator: " ")) to dismiss"
    }

    // MARK: - KeyCombo Display Helpers

    /// Converts a modifier mask + key into human-readable keycap labels like `["⌘", "Esc"]`.
    static func modifierAndKeyLabels(modifiers: NSEvent.ModifierFlags, key: Key) -> [String] {
        var labels: [String] = []

        if modifiers.contains(.control) { labels.append("⌃") }
        if modifiers.contains(.option) { labels.append("⌥") }
        if modifiers.contains(.shift) { labels.append("⇧") }
        if modifiers.contains(.command) { labels.append("⌘") }

        labels.append(keyLabel(for: key))
        return labels
    }

    /// Human-readable label for a single key.
    static func keyLabel(for key: Key) -> String {
        if let label = specialKeyLabels[key] {
            return label
        }
        // For letter/number/symbol keys, use the character representation
        let keyCode = Int(Sauce.shared.keyCode(for: key))
        return Sauce.shared.character(for: keyCode, cocoaModifiers: [])?.uppercased()
            ?? key.rawValue.uppercased()
    }

    private static let specialKeyLabels: [Key: String] = [
        .escape: "Esc", .return: "Return", .delete: "Delete",
        .tab: "Tab", .space: "Space",
        .upArrow: "↑", .downArrow: "↓", .leftArrow: "←", .rightArrow: "→",
        .home: "Home", .end: "End", .pageUp: "PgUp", .pageDown: "PgDn",
        .f1: "F1", .f2: "F2", .f3: "F3", .f4: "F4",
        .f5: "F5", .f6: "F6", .f7: "F7", .f8: "F8",
        .f9: "F9", .f10: "F10", .f11: "F11", .f12: "F12",
    ]

    // MARK: - Serialization

    private func decodedKeyCombo(from data: Data?) -> KeyCombo? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    private func encodedKeyCombo(_ keyCombo: KeyCombo) -> Data? {
        try? JSONEncoder().encode(keyCombo)
    }
}
