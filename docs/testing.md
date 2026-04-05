# Testing Guide

**Purpose**: Writing and running tests in Unmissable.
**Test Stack**: Swift Testing (`import Testing`) | XCUITest (UI tests only) | xcodebuild

---

## Test File Locations

| Test Type | Location | Naming Pattern |
|-----------|----------|----------------|
| Unit tests | `Tests/UnmissableTests/` | `[ClassName]Tests.swift` |
| Integration tests | `Tests/IntegrationTests/` | `[Feature]IntegrationTests.swift` |
| E2E tests | `Tests/E2ETests/` | `[Flow]E2ETests.swift` |
| UI tests (XCUITest) | `Tests/UITests/` | `[Feature]UITests.swift` |
| Test support | `Tests/TestSupport/` | Shared test doubles |

---

## Running Tests

All test commands go through `Scripts/test.sh`, which uses `xcodebuild` with a **4-worker parallel limit**, separates lint/build/test phases, and writes machine-readable results. Do **not** run bare `xcodebuild test` without worker limits. There is no `Package.swift` — `swift test` does not work here.

```bash
# Run all tests (recommended)
./Scripts/test.sh

# Run a specific test target
./Scripts/test.sh UnmissableTests

# Skip lint (useful when iterating on test fixes)
./Scripts/test.sh --skip-lint

# Clean build + all tests
./Scripts/test.sh --clean

# Lint only (strict — all warnings are errors)
./Scripts/enforce-lint.sh

# Full build + lint + format + test cycle
./Scripts/build.sh

# UI tests (XCUITest)
./Scripts/test-ui.sh
```

The script outputs a clear status line (`PASS`, `FAIL`, `BUILD_FAIL`, `LINT_FAIL`, or `TIMEOUT`) and writes a JSON summary to `.build/test-result.json`.

---

## How to Write a Unit Test

Unit, integration, and E2E tests all use **Swift Testing** (`import Testing`). XCTest is only used in `Tests/UITests/` (XCUITest requires it).

**Location**: `Tests/UnmissableTests/[ClassName]Tests.swift`

```swift
import Foundation
import Testing
@testable import Unmissable

@MainActor
struct [ClassName]Tests {

    private let sut: [ClassUnderTest]

    init() {
        sut = [ClassUnderTest](isTestEnvironment: true)
    }

    @Test
    func [methodName]_[scenario]_[expectedResult]() {
        // Given
        let input = [testInput]

        // When
        let result = sut.[methodUnderTest](input)

        // Then
        #expect(result == [expectedValue])
    }
}
```

For async setup:

```swift
@MainActor
struct [ClassName]Tests {
    private let sut: [ClassUnderTest]

    init() async throws {
        sut = try await [ClassUnderTest]()
    }

    @Test
    func someAsyncOperation() async throws {
        await sut.performAsyncOperation()
        #expect(sut.operationCompleted)
    }
}
```

---

## Test Naming Convention

**Pattern**: `[methodName]_[scenario]_[expectedResult]` (camelCase, not underscored — Swift Testing functions are plain methods)

```swift
@Test func extractLinks_withValidMeetURL_returnsOneLink() { ... }
@Test func extractLinks_withNoLinks_returnsEmptyArray() { ... }
@Test func showOverlay_whenFocusModeActive_doesNotShow() { ... }
```

---

## Testing @MainActor / Async Code

Apply `@MainActor` at the struct/class level when all tests in the type test `@MainActor` code:

```swift
@MainActor
struct SomeManagerTests {
    private let sut: SomeManager

    init() {
        sut = SomeManager(isTestEnvironment: true)
    }

    @Test
    func asyncOperation() async {
        await sut.performAsyncOperation()
        #expect(sut.operationCompleted)
    }
}
```

Key rules:
- Apply `@MainActor` to the struct/class, not individual test methods (unless mixing isolation)
- Use `async` test methods for async code
- Use `isTestEnvironment: true` when creating managers that otherwise touch system APIs

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


---

## UI Tests (XCUITest)

UI tests in `Tests/UITests/` use XCUITest, which requires XCTest as its base. This is the **only** place `import XCTest` and `XCTestCase` appear in the project.

```swift
import XCTest

final class [Feature]UITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test[Feature]_[scenario]() {
        // XCUITest assertions
    }
}
```

---

## Assertions Reference

| Assertion | Use Case |
|-----------|----------|
| `#expect(a == b)` | Values should be equal |
| `#expect(a != b)` | Values should differ |
| `#expect(condition)` | Boolean should be true |
| `#expect(!condition)` | Boolean should be false |
| `#expect(optional == nil)` | Optional should be nil |
| `#expect(optional != nil)` | Optional should have value |
| `let value = try #require(optional)` | Unwrap optional or fail test |
| `#expect(throws: ErrorType.self) { try x }` | Should throw specific error |
| `#expect(throws: Never.self) { try x }` | Should not throw |

---

## Lint-Enforced Test Quality

These patterns produce **errors** in test files:

| Banned Pattern | Why | Use Instead |
|---------------|-----|-------------|
| `#expect(x != nil)` alone | Shallow — proves existence, not correctness | `let v = try #require(x)` + assert the value |
| `#expect(array.contains(x))` without message | Poor failure messages | Add message: `#expect(array.contains(x), "Expected ...")` |
| `Task.sleep(...)` | Causes flaky tests | `TestUtilities.waitForAsync` |
| `OverlayManager()` | Creates real fullscreen UI | `TestSafeOverlayManager` |
| `AppState()` | Creates real OverlayManager | Inject dependencies |
| `NSApplication.shared` | Interacts with window server | Mock the window layer |
| `print("debug...")` | Noise in test output | Use `#expect` to verify values |

---

## Common Mistakes

**Setup**:
- Don't use `XCTestCase` for unit/integration/E2E tests. Do use `struct`/`class` with Swift Testing.
- Don't use `override func setUp()` / `tearDown()`. Do use `init()` / `deinit`.
- Don't create real UI managers in tests. Do use `isTestEnvironment: true`.

**Async**:
- Don't use `sleep()` or `Task.sleep()`. Do use `async/await` or `TestUtilities.waitForAsync`.
- Don't forget `@MainActor` when testing `@MainActor` classes.

**Assertions**:
- Don't use bare `#expect(condition)` for equality. Do use `#expect(actual == expected)`.
- Don't skip edge cases (nil, empty, boundary). Do test happy path AND error paths.

**Isolation**:
- Don't rely on test execution order. Do make each test independent.
- Don't share mutable state between tests. Do reset state in `init()`.

**Framework choice**:
- Don't use `import XCTest` in unit/integration/E2E tests.
- Do use `import XCTest` only in `Tests/UITests/` (XCUITest requirement).

## On-Demand References

| Domain | Serena Memory |
|--------|---------------|
| Test pruning decisions | `test_pruning_nonlegacy_overlay_pass2` |
| Overlay test stabilization | `system_integration_overlay_visibility_stabilization_2026_02_21` |
