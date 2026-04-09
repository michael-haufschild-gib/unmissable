import AppKit
import Foundation
import Observation
import OSLog

/// Observes system sleep/wake transitions via `NSWorkspace` notifications
/// and provides a centralized lifecycle hook for all polling managers.
///
/// Managers register callbacks that fire on sleep (to suspend timers)
/// and on wake (to resume with fresh state). This prevents stale
/// `Task.sleep` completions from flooding the MainActor on wake and
/// eliminates unnecessary CPU work while the machine is asleep.
@MainActor
@Observable
final class SystemSleepObserver {
    private let logger = Logger(category: "SystemSleepObserver")

    /// Whether the system is currently awake. Managers can check this
    /// before starting work that should be skipped during sleep.
    private(set) var isSystemAwake: Bool = true

    /// Registered sleep callbacks, keyed for removal.
    @ObservationIgnored
    private var sleepCallbacks: [String: @MainActor () -> Void] = [:]

    /// Registered wake callbacks, keyed for removal.
    @ObservationIgnored
    private var wakeCallbacks: [String: @MainActor () -> Void] = [:]

    @ObservationIgnored
    private nonisolated(unsafe) var willSleepObserver: NSObjectProtocol?
    @ObservationIgnored
    private nonisolated(unsafe) var didWakeObserver: NSObjectProtocol?

    init() {
        willSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWillSleep()
            }
        }

        didWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDidWake()
            }
        }

        logger.info("System sleep observer initialized")
    }

    deinit {
        if let willSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(willSleepObserver)
        }
        if let didWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(didWakeObserver)
        }
    }

    /// Registers a callback pair for sleep/wake transitions.
    /// - Parameters:
    ///   - key: Unique identifier for this registration (for removal).
    ///   - onSleep: Called when the system is about to sleep.
    ///   - onWake: Called when the system wakes from sleep.
    func register(
        key: String,
        onSleep: @escaping @MainActor () -> Void,
        onWake: @escaping @MainActor () -> Void,
    ) {
        sleepCallbacks[key] = onSleep
        wakeCallbacks[key] = onWake
        logger.debug("Registered sleep/wake callbacks for '\(key)'")
    }

    /// Removes a previously registered callback pair.
    func unregister(key: String) {
        sleepCallbacks.removeValue(forKey: key)
        wakeCallbacks.removeValue(forKey: key)
    }

    private func handleWillSleep() {
        logger.info("System will sleep — suspending \(self.sleepCallbacks.count) managers")
        isSystemAwake = false
        for (key, callback) in sleepCallbacks {
            logger.debug("Suspending '\(key)'")
            callback()
        }
    }

    private func handleDidWake() {
        logger.info("System did wake — resuming \(self.wakeCallbacks.count) managers")
        isSystemAwake = true
        for (key, callback) in wakeCallbacks {
            logger.debug("Resuming '\(key)'")
            callback()
        }
    }
}
