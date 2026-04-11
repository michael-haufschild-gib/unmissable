import AppKit
import Foundation
import Testing
@testable import Unmissable

/// Unit tests for the ref-counted NSApp.setActivationPolicy coordinator.
///
/// Uses the `apply` closure seam on `ActivationPolicyManager.init` so no tests
/// ever touch `NSApp`. Each test records the sequence of `(policy, accepted)`
/// results it observed and asserts against that recorder.
@MainActor
struct ActivationPolicyManagerTests {
    /// Captures the full transcript of policy calls made by the manager.
    final class PolicyRecorder {
        private(set) var calls: [NSApplication.ActivationPolicy] = []
        var nextResult = true

        func apply(_ policy: NSApplication.ActivationPolicy) -> Bool {
            calls.append(policy)
            return nextResult
        }
    }

    // MARK: - Acquire

    @Test
    func acquire_firstCall_switchesToRegular() {
        let recorder = PolicyRecorder()
        let sut = ActivationPolicyManager(
            apply: { recorder.apply($0) },
            keepRegularWhenIdle: false,
        )

        sut.acquireRegularPolicy()

        #expect(recorder.calls == [.regular])
        #expect(sut.isInRegularPolicy)
    }

    @Test
    func acquire_multipleCalls_switchesOnlyOnce() {
        let recorder = PolicyRecorder()
        let sut = ActivationPolicyManager(
            apply: { recorder.apply($0) },
            keepRegularWhenIdle: false,
        )

        sut.acquireRegularPolicy()
        sut.acquireRegularPolicy()
        sut.acquireRegularPolicy()

        #expect(
            recorder.calls == [.regular],
            "Only the first acquire should invoke setActivationPolicy",
        )
        #expect(sut.isInRegularPolicy)
    }

    // MARK: - Release

    @Test
    func release_afterSingleAcquire_revertsToAccessory() {
        let recorder = PolicyRecorder()
        let sut = ActivationPolicyManager(
            apply: { recorder.apply($0) },
            keepRegularWhenIdle: false,
        )

        sut.acquireRegularPolicy()
        sut.releaseRegularPolicy()

        #expect(recorder.calls == [.regular, .accessory])
        #expect(!sut.isInRegularPolicy)
    }

    @Test
    func release_withOutstandingAcquisitions_doesNotRevert() {
        let recorder = PolicyRecorder()
        let sut = ActivationPolicyManager(
            apply: { recorder.apply($0) },
            keepRegularWhenIdle: false,
        )

        sut.acquireRegularPolicy()
        sut.acquireRegularPolicy()
        sut.releaseRegularPolicy()

        #expect(
            recorder.calls == [.regular],
            "Policy must remain .regular while one holder is still active",
        )
        #expect(sut.isInRegularPolicy)
    }

    @Test
    func release_withZeroCount_isNoOp() {
        let recorder = PolicyRecorder()
        let sut = ActivationPolicyManager(
            apply: { recorder.apply($0) },
            keepRegularWhenIdle: false,
        )

        sut.releaseRegularPolicy()

        #expect(recorder.calls.isEmpty, "Over-release must not call setActivationPolicy")
        #expect(!sut.isInRegularPolicy)
    }

    @Test
    func release_whenKeepRegularWhenIdle_skipsAccessoryRevert() {
        let recorder = PolicyRecorder()
        let sut = ActivationPolicyManager(
            apply: { recorder.apply($0) },
            keepRegularWhenIdle: true,
        )

        sut.acquireRegularPolicy()
        sut.releaseRegularPolicy()

        #expect(
            recorder.calls == [.regular],
            "UI-testing mode must keep the app in .regular — only the initial transition fires",
        )
        #expect(!sut.isInRegularPolicy, "Internal counter still drops to zero")
    }

    // MARK: - Sequences

    @Test
    func sequence_twoIndependentCycles_togglesTwice() {
        let recorder = PolicyRecorder()
        let sut = ActivationPolicyManager(
            apply: { recorder.apply($0) },
            keepRegularWhenIdle: false,
        )

        sut.acquireRegularPolicy()
        sut.releaseRegularPolicy()
        sut.acquireRegularPolicy()
        sut.releaseRegularPolicy()

        #expect(recorder.calls == [.regular, .accessory, .regular, .accessory])
    }

    @Test
    func sequence_overlappingAcquires_keepsPolicyRegularAcrossInnerRelease() {
        let recorder = PolicyRecorder()
        let sut = ActivationPolicyManager(
            apply: { recorder.apply($0) },
            keepRegularWhenIdle: false,
        )

        // Preferences window opens.
        sut.acquireRegularPolicy()
        // Onboarding window opens on top.
        sut.acquireRegularPolicy()
        // Onboarding closes — preferences still needs .regular.
        sut.releaseRegularPolicy()
        // Preferences closes — now we can revert.
        sut.releaseRegularPolicy()

        #expect(
            recorder.calls == [.regular, .accessory],
            "Only one transition in each direction despite nested acquisitions",
        )
    }

    // MARK: - Apply Failure

    @Test
    func applyFailure_doesNotCorruptCount() {
        let recorder = PolicyRecorder()
        recorder.nextResult = false
        let sut = ActivationPolicyManager(
            apply: { recorder.apply($0) },
            keepRegularWhenIdle: false,
        )

        // AppKit rejects the transition (simulated); the coordinator still
        // holds the logical reference count so a subsequent release balances.
        sut.acquireRegularPolicy()
        #expect(sut.isInRegularPolicy)

        sut.releaseRegularPolicy()
        #expect(!sut.isInRegularPolicy)
        #expect(
            recorder.calls == [.regular, .accessory],
            "Both transitions still attempted even though apply() returned false",
        )
    }
}
