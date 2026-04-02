import AppKit
import Foundation
import OSLog

/// Owns NotificationCenter observer tokens and removes them on deinit.
/// Separating this from the @MainActor class avoids nonisolated(unsafe) escape hatches.
private final class NotificationTokenBag: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
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

@MainActor
final class FocusModeManager: ObservableObject {
    private let logger = Logger(category: "FocusModeManager")

    @Published
    var isDoNotDisturbEnabled: Bool = false
    @Published
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
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkDoNotDisturbStatus()
            }
        })

        // Also monitor for Focus mode changes
        notificationTokens.add(NotificationCenter.default.addObserver(
            forName: .focusStateChanged,
            object: nil,
            queue: .main
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
                    "DND detection unavailable (parse failure): \(error.localizedDescription)"
                )
                self.dndDetectionAvailable = false
                self.isDoNotDisturbEnabled = false

            case .notFound:
                self.logger.warning(
                    "DND detection unavailable: preferences files not found at expected paths"
                )
                self.dndDetectionAvailable = false
                self.isDoNotDisturbEnabled = false
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

        return await readLegacyDNDPrefs(at: prefsPath)
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

    /// Legacy DND detection via native plist parsing of ncprefs.plist (macOS 11 and earlier).
    /// Reads the binary plist directly with PropertyListSerialization instead of shelling out to plutil.
    ///
    /// Fragility note: The `dnd_prefs` key structure is an undocumented Apple implementation detail.
    /// It may change or disappear in future macOS versions. This path is only reached on macOS 11
    /// and earlier (macOS 12+ uses Assertions.json above), so the risk is bounded.
    private nonisolated static func readLegacyDNDPrefs(at prefsPath: String) async -> DNDCheckResult {
        await Task.detached {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: prefsPath))
                guard data.count < 5_000_000 else {
                    // Safety: don't parse unreasonably large files
                    return DNDCheckResult.success(false)
                }
                guard let plist = try PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                ) as? [String: Any] else {
                    return .success(false)
                }

                // The dnd_prefs value is itself a nested plist (binary data blob)
                if let dndPrefsData = plist["dnd_prefs"] as? Data {
                    guard let dndPrefs = try PropertyListSerialization.propertyList(
                        from: dndPrefsData, options: [], format: nil
                    ) as? [String: Any] else {
                        return .success(false)
                    }
                    if let manuallyEnabled = dndPrefs["userPref"] as? [String: Any],
                       let enabled = manuallyEnabled["enabled"] as? Bool
                    {
                        return .success(enabled)
                    }
                }
                return .success(false)
            } catch {
                return .failure(error)
            }
        }.value
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

private enum DNDCheckResult {
    case success(Bool)
    case failure(Error)
    case notFound
}
