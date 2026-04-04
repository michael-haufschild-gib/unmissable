import OSLog
import ServiceManagement

/// Protocol for login item registration, enabling test injection.
@MainActor
protocol LoginItemManaging: Sendable {
    /// Registers or unregisters the app as a login item.
    func updateRegistration(enabled: Bool)

    /// Returns whether the app is currently registered as a login item in the system.
    var isRegisteredWithSystem: Bool { get }
}

/// Production implementation using SMAppService.
@MainActor
final class LoginItemManager: LoginItemManaging {
    private let logger = Logger(category: "LoginItemManager")

    func updateRegistration(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                logger.info("Registered as login item")
            } else {
                try service.unregister()
                logger.info("Unregistered login item")
            }
        } catch {
            logger.error("Failed to update login item registration: \(error.localizedDescription)")
        }
    }

    var isRegisteredWithSystem: Bool {
        SMAppService.mainApp.status == .enabled
    }
}

/// Test-safe implementation that records calls without touching the system.
@MainActor
final class TestSafeLoginItemManager: LoginItemManaging {
    /// All registration calls recorded in order. Empty means never called.
    /// Last element is the most recent value (replaces optional Bool tracking).
    private(set) var registrationHistory: [Bool] = []
    var stubbedIsRegistered = false

    func updateRegistration(enabled: Bool) {
        registrationHistory.append(enabled)
    }

    var isRegisteredWithSystem: Bool {
        stubbedIsRegistered
    }
}
