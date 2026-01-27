import AppKit
import Foundation
import OSLog

@MainActor
final class FocusModeManager: ObservableObject {
  private let logger = Logger(subsystem: "com.unmissable.app", category: "FocusModeManager")

  @Published var isDoNotDisturbEnabled: Bool = false

  private let preferencesManager: PreferencesManager
  private nonisolated(unsafe) var notificationObserver: NSObjectProtocol?
  private nonisolated(unsafe) var focusModeObserver: NSObjectProtocol?

  init(preferencesManager: PreferencesManager) {
    self.preferencesManager = preferencesManager
    setupNotifications()
    checkDoNotDisturbStatus()
  }

  deinit {
    if let observer = notificationObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = focusModeObserver {
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

    // Also monitor for Focus mode changes (macOS 12+)
    if #available(macOS 12.0, *) {
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
  }

  private func checkDoNotDisturbStatus() {
    // Move blocking process execution to background queue to prevent UI freeze
    Task.detached { [weak self] in
      // Get home directory path safely using FileManager
      let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
      let prefsPath = homeDirectory
        .appendingPathComponent("Library")
        .appendingPathComponent("Preferences")
        .appendingPathComponent("com.apple.ncprefs.plist")
        .path

      // Validate the path exists and is within expected directory
      guard prefsPath.hasPrefix(homeDirectory.path),
            FileManager.default.fileExists(atPath: prefsPath) else {
        await MainActor.run { [weak self] in
          self?.logger.warning("DND preferences file not found at expected path")
        }
        return
      }

      // Check Do Not Disturb status using plutil
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
      task.arguments = [
        "-extract", "dnd_prefs.dnd_manually_enabled", "raw",
        prefsPath,
      ]

      let pipe = Pipe()
      task.standardOutput = pipe
      task.standardError = pipe

      do {
        try task.run()

        // Use a timeout to prevent indefinite blocking if plutil hangs
        let timeoutTask = Task {
          try await Task.sleep(for: .seconds(3))
          if task.isRunning {
            task.terminate()
          }
        }

        task.waitUntilExit()
        timeoutTask.cancel()

        // Limit output size to prevent memory issues (DND status is just "0", "1", "true", or "false")
        let maxOutputSize = 100
        let fileHandle = pipe.fileHandleForReading
        let data = fileHandle.readData(ofLength: maxOutputSize)

        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(
          in: .whitespacesAndNewlines)
        {
          let newDNDStatus = output == "1" || output == "true"

          // Update UI on main thread
          await MainActor.run { [weak self] in
            guard let self = self else { return }
            if newDNDStatus != self.isDoNotDisturbEnabled {
              self.isDoNotDisturbEnabled = newDNDStatus
              self.logger.info("Do Not Disturb status changed: \(newDNDStatus)")
            }
          }
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.logger.error("Failed to check Do Not Disturb status: \(error.localizedDescription)")
        }
      }
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
    } else {
      logger.info("Suppressing overlay due to Do Not Disturb (override disabled)")
      return false
    }
  }

  func shouldPlaySound() -> Bool {
    // Sound follows the same logic as overlay visibility for now
    // Could be extended to have separate sound override settings
    return shouldShowOverlay()
  }
}
