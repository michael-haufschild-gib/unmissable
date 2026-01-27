import AppKit
import OSLog
import SwiftUI

/// Manages the preferences window with proper activation and foreground behavior
@MainActor
final class PreferencesWindowManager: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "PreferencesWindowManager")
    private var preferencesWindow: NSWindow?
    private let appState: AppState

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
            .customThemedEnvironment()
            .frame(minWidth: 650, minHeight: 450)

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
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
        // Activate the application first
        NSApp.activate(ignoringOtherApps: true)

        // Then bring the window to front and make it key
        window.makeKeyAndOrderFront(nil)

        // Ensure the window is properly focused
        window.orderFrontRegardless()

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
