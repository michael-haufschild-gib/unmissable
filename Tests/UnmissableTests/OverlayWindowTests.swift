import AppKit
import Testing
@testable import Unmissable

/// Verifies that `OverlayWindow` overrides the borderless-window defaults
/// that otherwise prevent keyboard input and normal main-window focus.
@MainActor
struct OverlayWindowTests {
    private let sut: OverlayWindow

    init() {
        sut = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true,
        )
    }

    @Test
    func canBecomeKey_returnsTrue() {
        #expect(
            sut.canBecomeKey,
            "Borderless overlay must accept key status for ESC dismiss to work",
        )
    }

    @Test
    func canBecomeMain_returnsTrue() {
        #expect(
            sut.canBecomeMain,
            "Borderless overlay must accept main status for proper multi-monitor focus",
        )
    }
}
