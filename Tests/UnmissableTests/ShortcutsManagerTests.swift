import Magnet
@testable import Unmissable
import XCTest

@MainActor
final class ShortcutsManagerTests: XCTestCase {
    private var sut: ShortcutsManager!
    private var overlayManager: TestSafeOverlayManager!

    override func setUp() async throws {
        try await super.setUp()
        cleanupHotKeys()
        sut = ShortcutsManager()

        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
    }

    override func tearDown() async throws {
        sut?.unregisterShortcuts()
        cleanupHotKeys()
        overlayManager = nil
        sut = nil
        try await super.tearDown()
    }

    func testSetup_whenDismissIdentifierAlreadyRegistered_keepsDismissShortcutNil() throws {
        let existingCombo = try XCTUnwrap(KeyCombo(key: .escape, cocoaModifiers: .command))
        let existingDismiss = HotKey(identifier: "dismiss_overlay", keyCombo: existingCombo) { _ in }
        XCTAssertTrue(existingDismiss.register())

        sut.setup(overlayManager: overlayManager)

        XCTAssertNil(sut.dismissShortcut)
        XCTAssertEqual(sut.joinShortcut?.identifier, "join_meeting")
    }

    func testSetup_whenJoinIdentifierAlreadyRegistered_keepsJoinShortcutNil() throws {
        let existingCombo = try XCTUnwrap(KeyCombo(key: .return, cocoaModifiers: .command))
        let existingJoin = HotKey(identifier: "join_meeting", keyCombo: existingCombo) { _ in }
        XCTAssertTrue(existingJoin.register())

        sut.setup(overlayManager: overlayManager)

        XCTAssertEqual(sut.dismissShortcut?.identifier, "dismiss_overlay")
        XCTAssertNil(sut.joinShortcut)
    }

    private func cleanupHotKeys() {
        _ = HotKeyCenter.shared.unregisterHotKey(with: "dismiss_overlay")
        _ = HotKeyCenter.shared.unregisterHotKey(with: "join_meeting")
    }
}
