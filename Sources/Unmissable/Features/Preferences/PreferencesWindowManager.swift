import AppKit
import OSLog
import SwiftUI

/// Manages the preferences window with proper activation and foreground behavior
@MainActor
final class PreferencesWindowManager: NSObject, ObservableObject {
    private let logger = Logger(category: "PreferencesWindowManager")
    private var preferencesWindow: NSWindow?
    private let appState: AppState

    private static let windowWidth: CGFloat = 650
    private static let windowHeight: CGFloat = 450

    init(appState: AppState) {
        self.appState = appState
    }

    /// Shows the preferences window and brings it to the foreground
    func showPreferences() {
        logger.info("Showing preferences window")

        if let existingWindow = preferencesWindow {
            // Window already exists, bring it to front
            logger.info("Bringing existing preferences window to front")
            activateWindow(existingWindow)
        } else {
            // Create new preferences window
            logger.info("Creating new preferences window")
            createPreferencesWindow()
        }
    }

    private func createPreferencesWindow() {
        let contentView = PreferencesView()
            .environmentObject(appState)
            .environmentObject(appState.calendar)
            .themed(themeManager: appState.themeManager)
            .frame(minWidth: Self.windowWidth, minHeight: Self.windowHeight)

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.windowWidth,
                height: Self.windowHeight,
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false,
        )

        window.title = "Unmissable Preferences"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("PreferencesWindow")

        // Ensure window can close properly without affecting app termination
        window.isReleasedWhenClosed = false

        // Set window delegate to handle close events
        window.delegate = self

        preferencesWindow = window
        activateWindow(window)
    }

    private func activateWindow(_ window: NSWindow) {
        // Activate the application first, then bring window to front.
        // orderFrontRegardless removed — NSApp.activate + makeKeyAndOrderFront is
        // the standard pattern. orderFrontRegardless bypasses the responder chain
        // and is unnecessary once the app is already activated.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        logger.info("Preferences window activated and brought to foreground")
    }
}

// MARK: - NSWindowDelegate

extension PreferencesWindowManager: NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        logger.info("Preferences window should close - allowing")
        return true
    }

    func windowWillClose(_: Notification) {
        logger.info("Preferences window will close")
        preferencesWindow = nil
    }
}
