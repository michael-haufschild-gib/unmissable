import Foundation
import Magnet
import Testing
@testable import Unmissable

@MainActor
struct ShortcutsManagerTests {
    private let sut: ShortcutsManager
    private let overlayManager: TestSafeOverlayManager

    init() {
        // Inline cleanup before init — can't call self methods before all properties are initialized
        _ = HotKeyCenter.shared.unregisterHotKey(with: "dismiss_overlay")
        _ = HotKeyCenter.shared.unregisterHotKey(with: "join_meeting")
        sut = ShortcutsManager(linkParser: LinkParser())
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
    }

    @Test
    func setup_whenDismissIdentifierAlreadyRegistered_keepsDismissShortcutNil() throws {
        defer {
            sut.unregisterShortcuts()
            cleanupHotKeys()
        }
        let existingCombo = try #require(KeyCombo(key: .escape, cocoaModifiers: .command))
        let existingDismiss = HotKey(identifier: "dismiss_overlay", keyCombo: existingCombo) { _ in }
        #expect(existingDismiss.register())

        sut.setup(overlayManager: overlayManager)

        #expect(sut.dismissShortcut == nil)
        #expect(sut.joinShortcut?.identifier == "join_meeting")
    }

    @Test
    func setup_whenJoinIdentifierAlreadyRegistered_keepsJoinShortcutNil() throws {
        defer {
            sut.unregisterShortcuts()
            cleanupHotKeys()
        }
        let existingCombo = try #require(KeyCombo(key: .return, cocoaModifiers: .command))
        let existingJoin = HotKey(identifier: "join_meeting", keyCombo: existingCombo) { _ in }
        #expect(existingJoin.register())

        sut.setup(overlayManager: overlayManager)

        #expect(sut.dismissShortcut?.identifier == "dismiss_overlay")
        #expect(sut.joinShortcut == nil)
    }

    private func cleanupHotKeys() {
        _ = HotKeyCenter.shared.unregisterHotKey(with: "dismiss_overlay")
        _ = HotKeyCenter.shared.unregisterHotKey(with: "join_meeting")
    }
}
