import AppKit
import OSLog

/// Reference-counted coordinator for `NSApp.setActivationPolicy`.
///
/// Menu-bar-only (`.accessory`) apps must switch to `.regular` when presenting
/// interactive windows, then restore `.accessory` when all such windows close.
/// Multiple managers (Preferences, Onboarding) may hold `.regular` concurrently;
/// this type ensures the policy reverts to `.accessory` only when *every* holder
/// has released.
@MainActor
final class ActivationPolicyManager {
    /// Closure that applies an activation policy. Defaults to `NSApp.setActivationPolicy`.
    /// Injected for tests so no real window-server interaction is required.
    typealias ApplyPolicy = @MainActor (NSApplication.ActivationPolicy) -> Bool

    private let logger = Logger(category: "ActivationPolicyManager")

    /// Number of outstanding `.regular` acquisitions.
    private var regularCount = 0

    private let apply: ApplyPolicy
    private let keepRegularWhenIdle: Bool

    /// True while at least one caller is holding `.regular` activation.
    /// Useful for diagnostics and tests; does not reflect UI-testing mode overrides.
    var isInRegularPolicy: Bool {
        regularCount > 0
    }

    /// - Parameters:
    ///   - apply: Closure that performs the actual policy change. Defaults to
    ///     `NSApp.setActivationPolicy`. Returns the `Bool` reported by AppKit
    ///     (`false` indicates the transition was rejected).
    ///   - keepRegularWhenIdle: When `true`, a final `release` will not revert
    ///     to `.accessory`. Used by UI tests that require `.regular` throughout
    ///     the session.
    init(
        apply: @escaping ApplyPolicy = { NSApp.setActivationPolicy($0) },
        keepRegularWhenIdle: Bool = AppRuntime.requiresRegularActivation,
    ) {
        self.apply = apply
        self.keepRegularWhenIdle = keepRegularWhenIdle
    }

    /// Requests `.regular` activation policy.
    ///
    /// The first acquisition switches the policy; subsequent calls only
    /// increment the reference count.
    func acquireRegularPolicy() {
        regularCount += 1
        if regularCount == 1 {
            applyPolicy(.regular)
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

        guard !keepRegularWhenIdle else {
            logger.info("UI testing mode — keeping .regular activation policy")
            return
        }

        applyPolicy(.accessory)
        logger.info("Activation policy → .accessory")
    }

    private func applyPolicy(_ policy: NSApplication.ActivationPolicy) {
        let accepted = apply(policy)
        if !accepted {
            logger.error("Activation policy apply(\(String(describing: policy))) rejected by AppKit")
        }
    }
}
