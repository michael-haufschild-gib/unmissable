import AppKit
import OSLog

/// Detects the frontmost application using `NSWorkspace`.
///
/// Used by `OverlayManager` to suppress the full-screen overlay when the user
/// already has the meeting's native app in the foreground.
/// All methods are synchronous and require no permissions.
@MainActor
final class ForegroundAppDetector: ForegroundAppDetecting {
    private let logger = Logger(category: "ForegroundAppDetector")

    func isMeetingAppInForeground(for provider: Provider) -> Bool {
        let bundleIDs = provider.knownBundleIdentifiers
        guard !bundleIDs.isEmpty else { return false }

        guard let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }

        let match = bundleIDs.contains(frontBundleID)
        if match {
            logger.info(
                "Meeting app detected in foreground: \(frontBundleID) for \(provider.displayName)",
            )
        }
        return match
    }
}
