import Foundation
import Testing
@testable import Unmissable

@MainActor
struct ContinuationCoordinatorTests {
    // MARK: - Resume Returning

    @Test
    func resumeReturning_deliversValue() async throws {
        let coordinator = ContinuationCoordinator<String>()

        let result = try await withCheckedThrowingContinuation { continuation in
            coordinator.setContinuation(continuation)
            coordinator.resume(returning: "hello")
        }

        #expect(result == "hello")
        #expect(coordinator.isCompleted)
    }

    // MARK: - Resume Throwing

    @Test
    func resumeThrowing_deliversError() async {
        let coordinator = ContinuationCoordinator<String>()

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                coordinator.setContinuation(continuation)
                coordinator.resume(throwing: TestError.intentional)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error as? TestError == .intentional)
        }

        #expect(coordinator.isCompleted)
    }

    // MARK: - Exactly-Once Guarantee

    @Test
    func doubleResume_onlyFirstHasEffect() async throws {
        let coordinator = ContinuationCoordinator<String>()

        let result = try await withCheckedThrowingContinuation { continuation in
            coordinator.setContinuation(continuation)
            coordinator.resume(returning: "first")
            // Second resume should be silently ignored (no crash)
            coordinator.resume(returning: "second")
        }

        #expect(result == "first", "Only the first resume should take effect")
    }

    @Test
    func resumeAfterError_isIgnored() async {
        let coordinator = ContinuationCoordinator<String>()

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                coordinator.setContinuation(continuation)
                coordinator.resume(throwing: TestError.intentional)
                // This should be silently ignored
                coordinator.resume(returning: "late value")
            }
            Issue.record("Expected error")
        } catch {
            #expect(error as? TestError == .intentional)
        }
    }

    // MARK: - Timeout

    @Test
    func timeout_resumesWithError() async {
        let coordinator = ContinuationCoordinator<String>()

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                coordinator.setContinuation(continuation)
                coordinator.startTimeout(seconds: 1) {
                    TestError.timedOut
                }
                // Don't call resume — let timeout fire
            }
            Issue.record("Expected timeout error")
        } catch {
            #expect(error as? TestError == .timedOut)
        }

        #expect(coordinator.isCompleted)
    }

    @Test
    func resumeBeforeTimeout_cancelsTimeout() async throws {
        let coordinator = ContinuationCoordinator<String>()

        let result = try await withCheckedThrowingContinuation { continuation in
            coordinator.setContinuation(continuation)
            coordinator.startTimeout(seconds: 10) {
                TestError.timedOut
            }
            // Resume immediately — timeout should be cancelled
            coordinator.resume(returning: "fast")
        }

        #expect(result == "fast")
        #expect(coordinator.isCompleted)
    }

    // MARK: - Stress: Concurrent Resume Calls

    @Test
    func concurrentResumeCalls_onlyFirstDelivers() async throws {
        let coordinator = ContinuationCoordinator<String>()

        let result = try await withCheckedThrowingContinuation { continuation in
            coordinator.setContinuation(continuation)

            // Launch multiple concurrent resume attempts
            for i in 0 ..< 10 {
                Task { @MainActor in
                    coordinator.resume(returning: "attempt-\(i)")
                }
            }
        }

        // Only one value should have been delivered
        #expect(result.hasPrefix("attempt-"), "Should receive one of the attempt values")
        #expect(coordinator.isCompleted)
    }

    @Test
    func concurrentResumeAndThrow_onlyFirstDelivers() async {
        let coordinator = ContinuationCoordinator<String>()

        do {
            let result = try await withCheckedThrowingContinuation { continuation in
                coordinator.setContinuation(continuation)

                // Some tasks resume with value, some with error
                for i in 0 ..< 5 {
                    Task { @MainActor in
                        if i.isMultiple(of: 2) {
                            coordinator.resume(returning: "value-\(i)")
                        } else {
                            coordinator.resume(throwing: TestError.intentional)
                        }
                    }
                }
            }
            // If we got here, a value was delivered
            #expect(result.hasPrefix("value-"))
        } catch {
            // If we got here, an error was delivered
            #expect(error as? TestError == .intentional)
        }

        #expect(coordinator.isCompleted)
    }

    // MARK: - Fresh Coordinator State

    @Test
    func newCoordinatorIsNotCompleted() {
        let coordinator = ContinuationCoordinator<String>()
        #expect(!coordinator.isCompleted)
    }

    // MARK: - Test Helpers

    private enum TestError: Error, Equatable {
        case intentional
        case timedOut
    }
}
