import Foundation

/// Coordinates a CheckedContinuation with timeout support, ensuring exactly-once resumption.
///
/// ## Guarantees
/// 1. Exactly-once continuation resumption (prevents crashes from double-resume)
/// 2. Timeout handling (prevents continuation leaks if callback never fires)
/// 3. Thread safety via @MainActor isolation — all mutable state accessed only on MainActor
/// 4. Proper cleanup of timeout tasks
///
/// ## Design Decisions
///
/// **`@unchecked Sendable`**: Required because this object is passed into AppAuth's
/// non-Sendable callback closures that execute on arbitrary threads. The closure dispatches
/// back to MainActor before any state access, so @MainActor provides the real isolation.
///
/// **`preconditionFailure` in `resumeInternal`**: Deliberately chosen over `assertionFailure`.
/// If resume is called before setContinuation, the continuation would be permanently leaked
/// (never resumed), causing the caller's `withCheckedThrowingContinuation` to hang forever.
/// A crash is preferable to a silent hang in this case, and the condition indicates a
/// programming error that must be fixed — not a recoverable runtime state.
@MainActor
final class ContinuationCoordinator<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Error>?
    private var timeoutTask: Task<Void, Never>?
    private(set) var isCompleted = false

    init() {}

    /// Stores the continuation for later resumption.
    /// Must be called exactly once before any resume calls.
    func setContinuation(_ continuation: CheckedContinuation<T, Error>) {
        precondition(self.continuation == nil, "Continuation already set")
        self.continuation = continuation
    }

    /// Starts a timeout that will resume the continuation with an error if not completed in time.
    func startTimeout(seconds: Int, onTimeout: @escaping @MainActor () -> Error) {
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))

                guard let self, !self.isCompleted else { return }

                let error = onTimeout()
                resumeInternal(with: .failure(error))
            } catch {
                // Task was cancelled — normal path when auth completes before timeout
            }
        }
    }

    /// Resumes the continuation with a successful value.
    /// Safe to call multiple times — only the first call has effect.
    func resume(returning value: T) {
        resumeInternal(with: .success(value))
    }

    /// Resumes the continuation with an error.
    /// Safe to call multiple times — only the first call has effect.
    func resume(throwing error: Error) {
        resumeInternal(with: .failure(error))
    }

    private func resumeInternal(with result: Result<T, Error>) {
        guard !isCompleted else { return }
        isCompleted = true

        timeoutTask?.cancel()
        timeoutTask = nil

        guard let continuation else {
            preconditionFailure("Continuation not set before resume")
        }
        self.continuation = nil

        switch result {
        case let .success(value):
            continuation.resume(returning: value)

        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
