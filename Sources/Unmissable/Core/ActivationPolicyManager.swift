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

    /// Number of outstanding `.regular` acquisitions — pure ownership refcount.
    /// Always incremented on `acquireRegularPolicy()` and decremented on
    /// `releaseRegularPolicy()`, regardless of whether AppKit actually accepted
    /// the transition. Keeping this divorced from the applied state means a
    /// failed first-apply cannot wedge the coordinator.
    private var regularCount = 0

    /// Tracks whether AppKit has actually accepted a `.regular` transition.
    /// Updated only when `apply(...)` returns `true`. `acquireRegularPolicy()`
    /// uses this flag — not `regularCount` — to decide whether to re-attempt
    /// the apply, so a previously rejected transition is retried on the next
    /// acquisition instead of being silently skipped via the "retained" branch.
    private var isRegularApplied = false

    private let apply: ApplyPolicy
    private let keepRegularWhenIdle: Bool

    /// True when AppKit is currently in `.regular` activation policy per the
    /// last successful transition. Distinct from `regularCount > 0` because a
    /// rejected apply can leave callers holding logical references while the
    /// app is still `.accessory`. Does not reflect UI-testing mode overrides.
    var isInRegularPolicy: Bool {
        isRegularApplied
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

        // Seed from the launch policy: when `keepRegularWhenIdle` is true,
        // AppDelegate has already forced `.regular` before this manager is
        // created. Starting at `false` would make `isInRegularPolicy` wrong
        // and trigger a redundant re-apply on the first `acquireRegularPolicy`.
        self.isRegularApplied = keepRegularWhenIdle
    }

    /// Requests `.regular` activation policy.
    ///
    /// Increments the refcount unconditionally, then attempts the apply
    /// whenever `.regular` is not currently applied. That means a rejected
    /// first-apply is retried on the next `acquireRegularPolicy()` call,
    /// instead of the coordinator quietly pretending it succeeded.
    func acquireRegularPolicy() {
        regularCount += 1
        guard !isRegularApplied else {
            logger.info("Regular policy retained (count: \(self.regularCount))")
            return
        }
        if applyPolicy(.regular) {
            isRegularApplied = true
            logger.info("Activation policy → .regular (count: \(self.regularCount))")
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

        if applyPolicy(.accessory) {
            isRegularApplied = false
            logger.info("Activation policy → .accessory")
        }
        // If AppKit rejects the accessory transition the applied flag stays
        // `true` — the app is still in `.regular` as far as the window server
        // is concerned, which matches reality.
    }

    /// Invokes the injected `apply` closure and logs failure. Returns `true`
    /// when AppKit accepted the transition, `false` otherwise — callers use
    /// this to gate their success-path `info` log so a rejected transition
    /// does not produce contradictory `info` + `error` entries.
    @discardableResult
    private func applyPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool {
        let accepted = apply(policy)
        if !accepted {
            logger.error("Activation policy apply(\(String(describing: policy))) rejected by AppKit")
        }
        return accepted
    }
}
