import AppKit
import Foundation
import OSLog

@MainActor
final class FocusModeManager: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "FocusModeManager")

    @Published var isDoNotDisturbEnabled: Bool = false

    private let preferencesManager: PreferencesManager
    nonisolated(unsafe) private var notificationObserver: NSObjectProtocol?
    nonisolated(unsafe) private var focusModeObserver: NSObjectProtocol?

    init(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
        setupNotifications()
        checkDoNotDisturbStatus()
    }

    deinit {
        // Capture nonisolated(unsafe) properties to local constants to avoid data race.
        // The capture itself is atomic (reading a reference), avoiding the race condition.
        // NotificationCenter.removeObserver() is thread-safe, so we can safely call it
        // synchronously from any thread.
        let notifObserver = notificationObserver
        let focusObserver = focusModeObserver
        if let observer = notifObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = focusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupNotifications() {
        // Monitor for Do Not Disturb state changes
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .dndPrefsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkDoNotDisturbStatus()
            }
        }

        // Also monitor for Focus mode changes
        focusModeObserver = NotificationCenter.default.addObserver(
            forName: .focusStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkDoNotDisturbStatus()
            }
        }
    }

    private func checkDoNotDisturbStatus() {
        // Use regular Task to maintain MainActor context, only the blocking Process call is isolated
        Task {
            let result = await Self.runDNDCheck()

            // Already on MainActor here - safe to update state directly
            switch result {
            case let .success(newDNDStatus):
                if newDNDStatus != self.isDoNotDisturbEnabled {
                    self.isDoNotDisturbEnabled = newDNDStatus
                    self.logger.info("Do Not Disturb status changed: \(newDNDStatus)")
                }
            case let .failure(error):
                self.logger.error("Failed to check Do Not Disturb status: \(error.localizedDescription)")
            case .notFound:
                self.logger.warning("DND preferences file not found at expected path")
            }
        }
    }

    /// Runs the plutil command to check DND status. Nonisolated to allow running on background thread.
    nonisolated private static func runDNDCheck() async -> DNDCheckResult {
        // Get home directory path safely using FileManager
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let prefsPath = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Preferences")
            .appendingPathComponent("com.apple.ncprefs.plist")
            .path

        // Validate the path exists and is within expected directory
        guard prefsPath.hasPrefix(homeDirectory.path),
              FileManager.default.fileExists(atPath: prefsPath)
        else {
            return .notFound
        }

        // Run blocking Process on detached task to avoid blocking MainActor
        return await Task.detached {
            // Check Do Not Disturb status using plutil
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            process.arguments = [
                "-extract", "dnd_prefs.dnd_manually_enabled", "raw",
                prefsPath,
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()

                // Use a timeout to prevent indefinite blocking if plutil hangs
                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(3))
                    if process.isRunning {
                        process.terminate()
                    }
                }

                process.waitUntilExit()
                timeoutTask.cancel()

                // Limit output size to prevent memory issues (DND status is just "0", "1", "true", or "false")
                let maxOutputSize = 100
                let fileHandle = pipe.fileHandleForReading
                let data = fileHandle.readData(ofLength: maxOutputSize)

                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) {
                    let newDNDStatus = output == "1" || output == "true"
                    return DNDCheckResult.success(newDNDStatus)
                }
                return .success(false)
            } catch {
                return .failure(error)
            }
        }.value
    }

    func shouldShowOverlay() -> Bool {
        // If Do Not Disturb is off, always show overlay
        guard isDoNotDisturbEnabled else {
            return true
        }

        // If Do Not Disturb is on, check preference
        if preferencesManager.overrideFocusMode {
            logger.info("Showing overlay despite Do Not Disturb (override enabled)")
            return true
        } else {
            logger.info("Suppressing overlay due to Do Not Disturb (override disabled)")
            return false
        }
    }

    func shouldPlaySound() -> Bool {
        // Sound follows the same logic as overlay visibility for now
        // Could be extended to have separate sound override settings
        shouldShowOverlay()
    }
}

// MARK: - DND Check Result

private enum DNDCheckResult: Sendable {
    case success(Bool)
    case failure(Error)
    case notFound
}
