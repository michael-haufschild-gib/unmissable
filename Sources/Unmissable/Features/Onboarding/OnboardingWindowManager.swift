import AppKit
import OSLog
import SwiftUI

/// Manages the onboarding window shown on first launch.
///
/// Follows the same pattern as ``PreferencesWindowManager``: a standalone
/// `NSWindow` hosting a SwiftUI view, activated in the foreground so it is
/// immediately visible despite the app being a menu-bar accessory.
@MainActor
final class OnboardingWindowManager: NSObject, ObservableObject {
    private let logger = Logger(category: "OnboardingWindowManager")
    private var window: NSWindow?
    private let appState: AppState

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
            .environmentObject(appState)
            .environmentObject(appState.calendar)
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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        logger.info("Onboarding window activated and brought to foreground")
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
    }
}
