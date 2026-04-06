# Testing Guide

**Purpose**: Writing and running tests in Unmissable.
**Test Stack**: Swift Testing (`import Testing`) | osascript UI tests | xcodebuild

---

## Test File Locations

| Test Type | Location | Naming Pattern |
|-----------|----------|----------------|
| Unit tests | `Tests/UnmissableTests/` | `[ClassName]Tests.swift` |
| Integration tests | `Tests/IntegrationTests/` | `[Feature]IntegrationTests.swift` |
| E2E tests | `Tests/E2ETests/` | `[Flow]E2ETests.swift` |
| UI tests (osascript) | `Scripts/test-ui.sh` | Shell functions: `test_[feature]_[scenario]` |
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

# UI tests (osascript-based, launches real app)
./Scripts/test-ui.sh
```

The script outputs a clear status line (`PASS`, `FAIL`, `BUILD_FAIL`, `LINT_FAIL`, or `TIMEOUT`) and writes a JSON summary to `.build/test-result.json`.

---

## How to Write a Unit Test

Unit, integration, and E2E tests all use **Swift Testing** (`import Testing`). UI tests use `Scripts/test-ui.sh` (osascript-based — see below).

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

## UI Tests (osascript)

UI tests live in `Scripts/test-ui.sh` and use **System Events AppleScript** to interact with the running app. XCUITest is not used because its synthesised events do not trigger mouse clicks correctly.

```bash
# Run all UI tests
./Scripts/test-ui.sh

# Build first, then run
./Scripts/test-ui.sh --build

# Run a single test
./Scripts/test-ui.sh test_menubar_click_opens_dropdown
```

### How to add a UI test

Add a shell function to `Scripts/test-ui.sh`:

```bash
test_my_feature_scenario() {
    launch_app --uitesting -hasCompletedOnboarding 1
    click_status_item >/dev/null
    sleep 1
    # Assert via osascript queries
    wait_for_windows 1 5
}
```

Then register it in the `main` section:

```bash
run_test "test_my_feature_scenario" test_my_feature_scenario
```

### Available helpers

| Helper | Purpose |
|--------|---------|
| `launch_app [args...]` | Launch the built app with arguments |
| `kill_app` | Terminate the app |
| `click_status_item` | Click the menu bar status item |
| `window_count` | Return number of app windows |
| `window_exists "title"` | Check if a window with title exists |
| `wait_for_windows N [timeout]` | Wait for at least N windows |
| `wait_for_window_gone "title" [timeout]` | Wait for window to close |
| `app_query 'script'` | Run AppleScript in System Events context |

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
- Don't use XCUITest for UI tests.
- Do use `Scripts/test-ui.sh` (osascript-based) for UI interaction tests.
