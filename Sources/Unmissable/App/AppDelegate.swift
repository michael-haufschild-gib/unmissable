import Cocoa
import OSLog

enum AppRuntime {
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
    static let requiresRegularActivation = ProcessInfo.processInfo.arguments.contains("--ui-testing-regular-activation")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(category: "AppDelegate")

    func applicationDidFinishLaunching(_: Notification) {
        logger.info("Unmissable app finished launching")
        AppDiagnostics.record(component: "AppDelegate", phase: "launch") {
            ["sessionId": AppDiagnostics.sessionId]
        }

        if AppRuntime.requiresRegularActivation {
            NSApp.setActivationPolicy(.regular)
            _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            logger.info("UI testing mode — forcing .regular activation policy")
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        // Register URL scheme handler
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL),
        )

        // Accessibility permission is now deferred to AppState — requested after
        // onboarding for first-time users, or on launch for returning users.
    }

    func applicationWillTerminate(_: Notification) {
        logger.info("Unmissable app will terminate")
        AppDiagnostics.record(component: "AppDelegate", phase: "terminate")
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        // Allow normal termination when explicitly requested (e.g., via Quit menu)
        logger.info("Application termination requested")
        return .terminateNow
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Show preferences when app is reopened with no visible windows
        if !flag {
            NotificationCenter.default.post(name: .showPreferences, object: nil)
        }
        return true
    }

    @objc
    func handleURLEvent(
        _ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor,
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString)
        else {
            logger.error("Failed to parse URL from Apple Event")
            return
        }

        logger.info("Received URL with scheme: \(url.scheme ?? "nil", privacy: .public)")

        // Handle OAuth callback using the configured redirect scheme
        if url.scheme == GoogleCalendarConfig.redirectScheme {
            logger.info("OAuth callback detected - posting notification")
            NotificationCenter.default.post(
                name: .oauthCallback,
                object: url,
            )
        } else {
            logger.warning("Received URL with unexpected scheme: \(url.scheme ?? "nil")")
        }
    }
}
