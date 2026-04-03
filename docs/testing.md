# Testing Guide

**Purpose**: Writing and running tests in Unmissable.
**Test Stack**: XCTest | SnapshotTesting (swift-snapshot-testing) | xcodebuild

---

## Test File Locations

| Test Type | Location | Naming Pattern |
|-----------|----------|----------------|
| Unit tests | `Tests/UnmissableTests/` | `[ClassName]Tests.swift` |
| Integration tests | `Tests/IntegrationTests/` | `[Feature]IntegrationTests.swift` |
| E2E tests | `Tests/E2ETests/` | `[Flow]E2ETests.swift` |
| Snapshot tests | `Tests/SnapshotTests/` | `[View]SnapshotTests.swift` |
| Test support | `Tests/TestSupport/` | Shared test doubles |

---

## Running Tests

All test commands go through `Scripts/test.sh`, which enforces a **4-worker parallel limit**, kills zombie processes, separates lint/build/test phases, and writes machine-readable results. Do **not** run bare `swift test` — it spawns unlimited parallel processes.

```bash
# Run all tests (recommended)
./Scripts/test.sh

# Run a specific test target
./Scripts/test.sh UnmissableTests

# Skip lint (useful when iterating on test fixes)
./Scripts/test.sh --skip-lint

# Clean build + all tests (fixes SPM lock issues)
./Scripts/test.sh --clean

# Lint only (strict — all warnings are errors)
./Scripts/enforce-lint.sh

# Full build + lint + format + test cycle
./Scripts/build.sh
```

The script outputs a clear status line (`PASS`, `FAIL`, `BUILD_FAIL`, `LINT_FAIL`, or `TIMEOUT`) and writes a JSON summary to `.build/test-result.json`.

---

## How to Write a Unit Test

**Location**: `Tests/UnmissableTests/[ClassName]Tests.swift`

```swift
import XCTest
@testable import Unmissable

final class [ClassName]Tests: XCTestCase {

    var sut: [ClassUnderTest]!

    override func setUp() {
        super.setUp()
        sut = [ClassUnderTest]()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func test[MethodName]_[Scenario]_[ExpectedResult]() {
        // Given
        let input = [testInput]

        // When
        let result = sut.[methodUnderTest](input)

        // Then
        XCTAssertEqual(result, [expectedValue])
    }
}
```

---

## Test Naming Convention

**Pattern**: `test[MethodName]_[Scenario]_[ExpectedResult]`

```swift
func testExtractLinks_withValidMeetURL_returnsOneLink()
func testExtractLinks_withNoLinks_returnsEmptyArray()
func testShowOverlay_whenFocusModeActive_doesNotShow()
```

---

## Testing @MainActor / Async Code

```swift
@MainActor
func testAsyncOperation() async {
    // Given
    let sut = SomeManager(isTestEnvironment: true)

    // When
    await sut.performAsyncOperation()

    // Then
    XCTAssertTrue(sut.operationCompleted)
}
```

Key rules:
- Use `@MainActor` on test methods that test `@MainActor` classes
- Use `async` test methods for async code
- Use `isTestEnvironment: true` when creating managers

---

## Test Data Helpers

```swift
extension Event {
    static func testEvent(
        id: String = "test-123",
        title: String = "Test Meeting",
        startDate: Date = Date(),
        endDate: Date = Date().addingTimeInterval(3600)
    ) -> Event {
        Event(id: id, title: title, startDate: startDate,
              endDate: endDate, calendarId: "primary")
    }
}
```

---

## Snapshot Testing

For UI components (requires SnapshotTesting dependency):

```swift
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Unmissable

final class [View]SnapshotTests: XCTestCase {

    func testViewAppearance() {
        let view = [SomeView]()
        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: 400, height: 300))
        )
    }
}
```

First run creates reference snapshot in `__Snapshots__/`. Subsequent runs compare against it.

---

## Assertions Reference

| Assertion | Use Case |
|-----------|----------|
| `XCTAssertEqual(a, b)` | Values should be equal |
| `XCTAssertNotEqual(a, b)` | Values should differ |
| `XCTAssertTrue(x)` | Boolean should be true |
| `XCTAssertFalse(x)` | Boolean should be false |
| `XCTAssertNil(x)` | Optional should be nil |
| `XCTAssertNotNil(x)` | Optional should have value |
| `XCTAssertThrowsError(try x)` | Should throw error |
| `XCTAssertNoThrow(try x)` | Should not throw |

---

## Lint-Enforced Test Quality

These patterns produce **errors** in test files:

| Banned Pattern | Why | Use Instead |
|---------------|-----|-------------|
| `XCTAssertNotNil(x)` alone | Shallow — proves existence, not correctness | `XCTUnwrap` + assert the value |
| `XCTAssertTrue(.contains(...))` | Poor failure messages | `XCTAssertEqual` or specific matcher |
| `XCTAssert(x is Type)` | Type-only check is shallow | Assert behavior or values |
| `Task.sleep(...)` | Causes flaky tests | `TestUtilities.waitForAsync` |
| `OverlayManager()` | Creates real fullscreen UI | `TestSafeOverlayManager` |
| `AppState()` | Creates real OverlayManager | Inject dependencies |
| `NSApplication.shared` | Interacts with window server | Mock the window layer |
| `print("debug...")` | Noise in test output | `XCTAssert` to verify values |

---

## Common Mistakes

**Setup**:
- Don't create real UI managers in tests. Do use `isTestEnvironment: true`.
- Don't forget `sut = nil` in `tearDown()`. Do clean up state between tests.

**Async**:
- Don't use `sleep()` or `Task.sleep()`. Do use `async/await` or `TestUtilities.waitForAsync`.
- Don't forget `@MainActor` when testing `@MainActor` classes.

**Assertions**:
- Don't use bare `XCTAssert(condition)` for equality. Do use `XCTAssertEqual(actual, expected)`.
- Don't skip edge cases (nil, empty, boundary). Do test happy path AND error paths.

**Isolation**:
- Don't rely on test execution order. Do make each test independent.
- Don't share mutable state between tests. Do reset state in `setUp()`/`tearDown()`.

## On-Demand References

| Domain | Serena Memory |
|--------|---------------|
| Test pruning decisions | `test_pruning_nonlegacy_overlay_pass2` |
| Overlay test stabilization | `system_integration_overlay_visibility_stabilization_2026_02_21` |
