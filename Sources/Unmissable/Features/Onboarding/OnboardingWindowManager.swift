import AppKit
import Observation
import OSLog
import SwiftUI

/// Manages the onboarding window shown on first launch.
///
/// Follows the same pattern as ``PreferencesWindowManager``: a standalone
/// `NSWindow` hosting a SwiftUI view, activated in the foreground so it is
/// immediately visible despite the app being a menu-bar accessory.
@Observable
final class OnboardingWindowManager: NSObject {
    private enum Activation {
        static let settleDelay: TimeInterval = 0.2
    }

    private let logger = Logger(category: "OnboardingWindowManager")
    private var window: NSWindow?
    private let appState: AppState

    /// Whether the onboarding window is currently visible. Observable by tests.
    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }

    /// Whether the onboarding window is the key window. Observable by tests.
    var isWindowKey: Bool {
        window?.isKeyWindow ?? false
    }

    /// The onboarding window's title, or nil if no window exists.
    var windowTitle: String? {
        window?.title
    }

    private static let windowWidth: CGFloat = 500
    private static let windowHeight: CGFloat = 600

    init(appState: AppState) {
        self.appState = appState
    }

    /// Creates and displays the onboarding window, bringing it to the foreground.
    func showOnboarding() {
        if let existingWindow = window {
            logger.info("Bringing existing onboarding window to front")
            activateWindow(existingWindow)
            return
        }

        logger.info("Creating onboarding window")

        let contentView = OnboardingView()
            .environment(appState)
            .environment(appState.calendar)
            .themed(themeManager: appState.themeManager)
            .frame(
                minWidth: Self.windowWidth,
                minHeight: Self.windowHeight,
            )

        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.windowWidth,
                height: Self.windowHeight,
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )

        newWindow.title = "Welcome to Unmissable"
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.collectionBehavior = [.moveToActiveSpace]
        newWindow.hidesOnDeactivate = false
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        window = newWindow
        activateWindow(newWindow)
    }

    /// Programmatically closes the onboarding window.
    func close() {
        logger.info("Closing onboarding window")
        window?.close()
        window = nil
    }

    private func activateWindow(_ window: NSWindow) {
        // LSUIElement/menu bar apps need a stronger activation sequence than a
        // normal windowed app. On newer macOS builds, `makeKeyAndOrderFront`
        // alone still leaves the window visible but not frontmost/hittable.
        // Promote to `.regular`, activate all windows, then force the window to
        // the front and finally make it key.
        NSApp.setActivationPolicy(.regular)
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + Activation.settleDelay) {
            _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            window.makeMain()
            window.makeKeyAndOrderFront(nil)
        }
        logger.info("Onboarding window activated and ordered front")
    }
}

// MARK: - NSWindowDelegate

extension OnboardingWindowManager: NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        logger.info("Onboarding window should close — allowing")
        return true
    }

    func windowWillClose(_: Notification) {
        logger.info("Onboarding window will close")
        window = nil

        guard !AppRuntime.requiresRegularActivation else {
            logger.info("UI testing mode — keeping .regular activation policy")
            return
        }

        // Restore menu-bar-only mode now that the onboarding window is gone.
        NSApp.setActivationPolicy(.accessory)
        logger.info("Restored .accessory activation policy")
    }
}
