import AppKit
import Observation
import OSLog
import SwiftUI

/// Manages the preferences window with proper activation and foreground behavior
@Observable
final class PreferencesWindowManager: NSObject {
    private enum Activation {
        static let settleDelay: TimeInterval = 0.2
    }

    private let logger = Logger(category: "PreferencesWindowManager")
    private var preferencesWindow: NSWindow?
    private unowned let appState: AppState

    /// Whether the preferences window is currently visible. Observable by tests.
    var isWindowVisible: Bool {
        preferencesWindow?.isVisible ?? false
    }

    /// The preferences window's title, or nil if no window exists.
    var windowTitle: String? {
        preferencesWindow?.title
    }

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
            .environment(appState)
            .environment(appState.calendar)
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
        window.collectionBehavior = [.moveToActiveSpace]
        window.hidesOnDeactivate = false
        window.setFrameAutosaveName("PreferencesWindow")

        // Ensure window can close properly without affecting app termination
        window.isReleasedWhenClosed = false

        // Set window delegate to handle close events
        window.delegate = self

        preferencesWindow = window
        appState.activationPolicyManager.acquireRegularPolicy()
        activateWindow(window)
    }

    /// Programmatically closes the preferences window.
    func close() {
        logger.info("Closing preferences window")
        preferencesWindow?.close()
        preferencesWindow = nil
    }

    private func activateWindow(_ window: NSWindow) {
        guard !AppRuntime.isRunningTests else {
            window.orderFrontRegardless()
            logger.info("Test environment — skipping full window activation")
            return
        }

        // Correct activation sequence for LSUIElement / menu-bar apps (mirrors
        // OnboardingWindowManager): .regular policy is acquired when the window
        // is first created (createPreferencesWindow). Here we just bring it to
        // the front and activate the app so the system honours the request.
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        // Re-run after a brief settle. [weak window] ensures we do not retain
        // a window that is closed before the delay fires.
        Task { @MainActor [weak window] in
            try? await Task.sleep(for: .seconds(Activation.settleDelay))
            guard let window else { return }
            _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            window.makeMain()
            window.makeKeyAndOrderFront(nil)
        }

        logger.info("Preferences window activated and ordered front")
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
        appState.activationPolicyManager.releaseRegularPolicy()
    }
}
