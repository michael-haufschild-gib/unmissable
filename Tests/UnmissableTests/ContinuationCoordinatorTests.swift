@testable import Unmissable
import XCTest

@MainActor
final class ContinuationCoordinatorTests: XCTestCase {
    // MARK: - Resume Returning

    func testResumeReturning_deliversValue() async throws {
        let coordinator = ContinuationCoordinator<String>()

        let result = try await withCheckedThrowingContinuation { continuation in
            coordinator.setContinuation(continuation)
            coordinator.resume(returning: "hello")
        }

        XCTAssertEqual(result, "hello")
        XCTAssertTrue(coordinator.isCompleted)
    }

    // MARK: - Resume Throwing

    func testResumeThrowing_deliversError() async {
        let coordinator = ContinuationCoordinator<String>()

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                coordinator.setContinuation(continuation)
                coordinator.resume(throwing: TestError.intentional)
            }
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(error as? TestError, .intentional)
        }

        XCTAssertTrue(coordinator.isCompleted)
    }

    // MARK: - Exactly-Once Guarantee

    func testDoubleResume_onlyFirstHasEffect() async throws {
        let coordinator = ContinuationCoordinator<String>()

        let result = try await withCheckedThrowingContinuation { continuation in
            coordinator.setContinuation(continuation)
            coordinator.resume(returning: "first")
            // Second resume should be silently ignored (no crash)
            coordinator.resume(returning: "second")
        }

        XCTAssertEqual(result, "first", "Only the first resume should take effect")
    }

    func testResumeAfterError_isIgnored() async {
        let coordinator = ContinuationCoordinator<String>()

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                coordinator.setContinuation(continuation)
                coordinator.resume(throwing: TestError.intentional)
                // This should be silently ignored
                coordinator.resume(returning: "late value")
            }
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TestError, .intentional)
        }
    }

    // MARK: - Timeout

    func testTimeout_resumesWithError() async {
        let coordinator = ContinuationCoordinator<String>()

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                coordinator.setContinuation(continuation)
                coordinator.startTimeout(seconds: 1) {
                    TestError.timedOut
                }
                // Don't call resume — let timeout fire
            }
            XCTFail("Expected timeout error")
        } catch {
            XCTAssertEqual(error as? TestError, .timedOut)
        }

        XCTAssertTrue(coordinator.isCompleted)
    }

    func testResumeBeforeTimeout_cancelsTimeout() async throws {
        let coordinator = ContinuationCoordinator<String>()

        let result = try await withCheckedThrowingContinuation { continuation in
            coordinator.setContinuation(continuation)
            coordinator.startTimeout(seconds: 10) {
                TestError.timedOut
            }
            // Resume immediately — timeout should be cancelled
            coordinator.resume(returning: "fast")
        }

        XCTAssertEqual(result, "fast")
        XCTAssertTrue(coordinator.isCompleted)
    }

    // MARK: - Stress: Concurrent Resume Calls

    func testConcurrentResumeCalls_onlyFirstDelivers() async throws {
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
        XCTAssertTrue(result.hasPrefix("attempt-"), "Should receive one of the attempt values")
        XCTAssertTrue(coordinator.isCompleted)
    }

    func testConcurrentResumeAndThrow_onlyFirstDelivers() async {
        let coordinator = ContinuationCoordinator<String>()

        do {
            let result = try await withCheckedThrowingContinuation { continuation in
                coordinator.setContinuation(continuation)

                // Some tasks resume with value, some with error
                for i in 0 ..< 5 {
                    Task { @MainActor in
                        if i % 2 == 0 {
                            coordinator.resume(returning: "value-\(i)")
                        } else {
                            coordinator.resume(throwing: TestError.intentional)
                        }
                    }
                }
            }
            // If we got here, a value was delivered
            XCTAssertTrue(result.hasPrefix("value-"))
        } catch {
            // If we got here, an error was delivered
            XCTAssertEqual(error as? TestError, .intentional)
        }

        XCTAssertTrue(coordinator.isCompleted)
    }

    // MARK: - Fresh Coordinator State

    func testNewCoordinatorIsNotCompleted() {
        let coordinator = ContinuationCoordinator<String>()
        XCTAssertFalse(coordinator.isCompleted)
    }

    // MARK: - Test Helpers

    private enum TestError: Error, Equatable {
        case intentional
        case timedOut
    }
}
