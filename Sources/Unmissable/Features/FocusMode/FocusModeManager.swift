import AppKit
import Foundation
import Observation
import OSLog

/// Owns NotificationCenter observer tokens and removes them on deinit.
/// Separating this from the MainActor-isolated class avoids nonisolated(unsafe) escape hatches.
private final nonisolated class NotificationTokenBag: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []

    fileprivate func add(_ token: NSObjectProtocol) {
        lock.lock()
        tokens.append(token)
        lock.unlock()
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

@Observable
final class FocusModeManager {
    private let logger = Logger(category: "FocusModeManager")

    // MARK: - Constants

    private nonisolated static let maxAssertionsFileSize = 1_000_000

    var isDoNotDisturbEnabled: Bool = false
    private(set) var dndDetectionAvailable: Bool = true

    private let preferencesManager: PreferencesManager
    private let notificationTokens = NotificationTokenBag()
    /// Tracks the in-flight DND check task so rapid notification callbacks
    /// cancel the previous check rather than racing to update state.
    private var dndCheckTask: Task<Void, Never>?

    init(preferencesManager: PreferencesManager, isTestMode: Bool = false) {
        self.preferencesManager = preferencesManager
        guard !isTestMode else { return }
        setupNotifications()
        checkDoNotDisturbStatus()
    }

    private func setupNotifications() {
        // Monitor for Do Not Disturb state changes
        notificationTokens.add(NotificationCenter.default.addObserver(
            forName: .dndPrefsChanged,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkDoNotDisturbStatus()
            }
        })

        // Also monitor for Focus mode changes
        notificationTokens.add(NotificationCenter.default.addObserver(
            forName: .focusStateChanged,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkDoNotDisturbStatus()
            }
        })
    }

    private func checkDoNotDisturbStatus() {
        // Cancel any in-flight check to avoid racing when notifications fire rapidly
        dndCheckTask?.cancel()

        dndCheckTask = Task {
            let result = await Self.runDNDCheck()

            // If a newer check superseded this one, discard these results
            guard !Task.isCancelled else { return }

            // Already on MainActor here - safe to update state directly
            switch result {
            case let .success(newDNDStatus):
                if !self.dndDetectionAvailable {
                    self.logger.info("DND detection recovered")
                }
                self.dndDetectionAvailable = true
                if newDNDStatus != self.isDoNotDisturbEnabled {
                    self.isDoNotDisturbEnabled = newDNDStatus
                    self.logger.info("Do Not Disturb status changed: \(newDNDStatus)")
                }

            case let .failure(error):
                self.logger.warning(
                    "DND detection unavailable (parse failure): \(String(describing: type(of: error)))",
                )
                self.dndDetectionAvailable = false
                self.isDoNotDisturbEnabled = false

            case .notFound:
                self.logger.warning(
                    "DND detection unavailable: preferences files not found at expected paths",
                )
                self.dndDetectionAvailable = false
                self.isDoNotDisturbEnabled = false
            }
        }
    }

    /// Detects Focus/DND status via ~/Library/DoNotDisturb/DB/Assertions.json (macOS 12+).
    /// - Sandboxed: detection unavailable, defaults to "DND off" (overlays always shown)
    /// - Non-sandboxed: reads the assertions JSON database
    @concurrent
    private nonisolated static func runDNDCheck() async -> DNDCheckResult {
        // In sandboxed environments, filesystem-based DND detection is unavailable.
        // Default to "DND off" (overlays always shown) — safe for a meeting reminder app.
        let environment = ProcessInfo.processInfo.environment
        if environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            return .success(false)
        }

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

        let assertionsPath = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("DoNotDisturb")
            .appendingPathComponent("DB")
            .appendingPathComponent("Assertions.json")
            .path

        guard FileManager.default.fileExists(atPath: assertionsPath) else {
            return .notFound
        }

        return readAssertionsFile(at: assertionsPath)
    }

    /// Reads the modern Assertions.json to determine if any Focus mode is active.
    /// A non-empty "data" array with "storeAssertionRecords" indicates an active Focus.
    private nonisolated static func readAssertionsFile(at path: String) -> DNDCheckResult {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard data.count < maxAssertionsFileSize else {
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

    func shouldShowOverlay() -> Bool {
        // When DND detection is unavailable, always show (safe default for meeting reminders)
        guard dndDetectionAvailable else {
            return true
        }

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

private nonisolated enum DNDCheckResult {
    case success(Bool)
    case failure(Error)
    case notFound
}
