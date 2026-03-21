import AppKit
import Foundation
import OSLog

@MainActor
final class FocusModeManager: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "FocusModeManager")

    @Published
    var isDoNotDisturbEnabled: Bool = false

    private let preferencesManager: PreferencesManager
    private nonisolated(unsafe) var notificationObserver: NSObjectProtocol?
    private nonisolated(unsafe) var focusModeObserver: NSObjectProtocol?

    init(preferencesManager: PreferencesManager, isTestMode: Bool = false) {
        self.preferencesManager = preferencesManager
        guard !isTestMode else { return }
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

    /// Detects Focus/DND status using the most reliable method available.
    /// - Sandboxed: detection unavailable, defaults to "DND off" (overlays always shown)
    /// - Non-sandboxed macOS 12+: reads ~/Library/DoNotDisturb/DB/Assertions.json
    /// - Non-sandboxed legacy: reads ncprefs.plist via plutil
    private nonisolated static func runDNDCheck() async -> DNDCheckResult {
        // In sandboxed environments, filesystem-based DND detection is unavailable.
        // Default to "DND off" (overlays always shown) — safe for a meeting reminder app.
        let environment = ProcessInfo.processInfo.environment
        if environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            return .success(false)
        }

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

        // macOS 12+ stores Focus/DND assertions in a JSON database.
        // This is more reliable than the legacy ncprefs.plist approach.
        let assertionsPath = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("DoNotDisturb")
            .appendingPathComponent("DB")
            .appendingPathComponent("Assertions.json")
            .path

        if FileManager.default.fileExists(atPath: assertionsPath) {
            return await Task.detached {
                readAssertionsFile(at: assertionsPath)
            }.value
        }

        // Fallback: legacy ncprefs.plist (macOS 11 and earlier)
        let prefsPath = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Preferences")
            .appendingPathComponent("com.apple.ncprefs.plist")
            .path

        guard prefsPath.hasPrefix(homeDirectory.path),
              FileManager.default.fileExists(atPath: prefsPath)
        else {
            return .notFound
        }

        return await Task.detached {
            readLegacyDNDPrefs(at: prefsPath)
        }.value
    }

    /// Reads the modern Assertions.json to determine if any Focus mode is active.
    /// A non-empty "data" array with "storeAssertionRecords" indicates an active Focus.
    private nonisolated static func readAssertionsFile(at path: String) -> DNDCheckResult {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard data.count < 1_000_000 else {
                // Safety: don't parse unreasonably large files
                return .success(false)
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            // The assertions file contains "data" array with active focus records.
            // If "storeAssertionRecords" exists and is non-empty, a Focus mode is active.
            if let dataArray = json?["data"] as? [[String: Any]] {
                for entry in dataArray {
                    if let records = entry["storeAssertionRecords"] as? [[String: Any]],
                       !records.isEmpty
                    {
                        return .success(true)
                    }
                }
            }
            return .success(false)
        } catch {
            return .failure(error)
        }
    }

    /// Legacy DND detection via plutil on ncprefs.plist (macOS 11 and earlier).
    private nonisolated static func readLegacyDNDPrefs(at prefsPath: String) -> DNDCheckResult {
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

            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(3))
                if process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()
            timeoutTask.cancel()

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
        }

        logger.info("Suppressing overlay due to Do Not Disturb (override disabled)")
        return false
    }

    func shouldPlaySound() -> Bool {
        // Sound follows the same logic as overlay visibility for now
        // Could be extended to have separate sound override settings
        shouldShowOverlay()
    }
}

// MARK: - DND Check Result

private enum DNDCheckResult {
    case success(Bool)
    case failure(Error)
    case notFound
}
