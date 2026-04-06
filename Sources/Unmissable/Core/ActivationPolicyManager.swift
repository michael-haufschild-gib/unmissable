import AppKit
import OSLog

/// Reference-counted coordinator for `NSApp.setActivationPolicy`.
///
/// Menu-bar-only (`.accessory`) apps must switch to `.regular` when presenting
/// interactive windows, then restore `.accessory` when all such windows close.
/// Multiple managers (Preferences, Onboarding) may hold `.regular` concurrently;
/// this type ensures the policy reverts to `.accessory` only when *every* holder
/// has released.
final class ActivationPolicyManager {
    private let logger = Logger(category: "ActivationPolicyManager")

    /// Number of outstanding `.regular` acquisitions.
    private var regularCount = 0

    /// Requests `.regular` activation policy.
    ///
    /// The first acquisition switches the policy; subsequent calls only
    /// increment the reference count.
    func acquireRegularPolicy() {
        regularCount += 1
        if regularCount == 1 {
            NSApp.setActivationPolicy(.regular)
            logger.info("Activation policy → .regular (count: \(self.regularCount))")
        } else {
            logger.info("Regular policy retained (count: \(self.regularCount))")
        }
    }

    /// Releases one `.regular` acquisition.
    ///
    /// When the count reaches zero the policy reverts to `.accessory`, unless
    /// UI-testing mode requires `.regular` to stay active.
    func releaseRegularPolicy() {
        guard regularCount > 0 else {
            logger.warning("releaseRegularPolicy called with zero count — ignoring")
            return
        }

        regularCount -= 1

        guard regularCount == 0 else {
            logger.info("Regular policy still needed (count: \(self.regularCount))")
            return
        }

        guard !AppRuntime.requiresRegularActivation else {
            logger.info("UI testing mode — keeping .regular activation policy")
            return
        }

        NSApp.setActivationPolicy(.accessory)
        logger.info("Activation policy → .accessory")
    }
}
