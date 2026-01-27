# Testing Guide for LLM Coding Agents

**Purpose**: Instructions for writing and running tests in Unmissable.
**Test Stack**: XCTest | SnapshotTesting (swift-snapshot-testing) | xcodebuild

---

## Test File Locations

| Test Type | Location | Naming Pattern |
|-----------|----------|----------------|
| Unit tests | `Tests/UnmissableTests/` | `[ClassName]Tests.swift` |
| Integration tests | `Tests/IntegrationTests/` | `[Feature]IntegrationTests.swift` |
| Snapshot tests | `Tests/SnapshotTests/` | `[View]SnapshotTests.swift` |

---

## Running Tests

```bash
# Run all tests (quick)
swift test

# Run all tests with full build cycle
./Scripts/build.sh

# Run comprehensive test suite (unit + integration + UI + performance + memory)
./Scripts/run-comprehensive-tests.sh

# Run specific test file
swift test --filter [TestClassName]

# Run specific test method
swift test --filter [TestClassName]/[testMethodName]

# Run tests via xcodebuild (for CI or detailed output)
xcodebuild -scheme Unmissable -destination 'platform=macOS' test

# Run only unit tests
xcodebuild -scheme Unmissable -destination 'platform=macOS' test -only-testing:UnmissableTests
```

---

## How to Write a Unit Test

**Location**: `Tests/UnmissableTests/[ClassName]Tests.swift`

**Template**:
```swift
import XCTest

@testable import Unmissable

final class [ClassName]Tests: XCTestCase {

    // MARK: - Properties

    var sut: [ClassUnderTest]!  // System Under Test

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        sut = [ClassUnderTest]()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Tests

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

**Steps**:
1. Create file at `Tests/UnmissableTests/[ClassName]Tests.swift`
2. Import `XCTest` and `@testable import Unmissable`
3. Create class inheriting from `XCTestCase`
4. Add `setUp()` to initialize system under test
5. Add `tearDown()` to clean up
6. Write test methods starting with `test`

---

## Test Naming Convention

**Pattern**: `test[MethodName]_[Scenario]_[ExpectedResult]`

**Examples**:
```swift
func testExtractLinks_withValidMeetURL_returnsOneLink()
func testExtractLinks_withNoLinks_returnsEmptyArray()
func testEventInit_withRequiredFields_setsPropertiesCorrectly()
func testShowOverlay_whenFocusModeActive_doesNotShow()
```

---

## How to Test Models

**Template**:
```swift
import XCTest

@testable import Unmissable

final class [Model]Tests: XCTestCase {

    func test[Model]Initialization() {
        // Given
        let id = "test-123"
        let title = "Test Item"

        // When
        let model = [Model](
            id: id,
            title: title
            // ... other required fields
        )

        // Then
        XCTAssertEqual(model.id, id)
        XCTAssertEqual(model.title, title)
    }

    func test[Model]Equality() {
        // Given
        let model1 = [Model](id: "same-id", ...)
        let model2 = [Model](id: "same-id", ...)
        let model3 = [Model](id: "different-id", ...)

        // Then
        XCTAssertEqual(model1, model2)
        XCTAssertNotEqual(model1, model3)
    }

    func test[Model]ComputedProperty() {
        // Given
        let model = [Model](...)

        // When
        let result = model.[computedProperty]

        // Then
        XCTAssertEqual(result, [expected])
    }
}
```

---

## How to Test Managers/Services

**Template for @MainActor classes**:
```swift
import XCTest

@testable import Unmissable

final class [Manager]Tests: XCTestCase {

    var sut: [ManagerClass]!

    override func setUp() {
        super.setUp()
        // Use factory to create test-safe version
        sut = [ManagerClass](isTestEnvironment: true)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    @MainActor
    func testSomeMethod() async {
        // Given
        let input = [testData]

        // When
        await sut.someAsyncMethod(input)

        // Then
        XCTAssertTrue(sut.someState)
    }
}
```

**Key patterns**:
- Use `@MainActor` on test methods that test `@MainActor` classes
- Use `async` test methods for testing async code
- Use `isTestEnvironment: true` when creating managers

---

## How to Test Async Code

**Template**:
```swift
@MainActor
func testAsyncOperation() async {
    // Given
    let sut = SomeManager()

    // When
    await sut.performAsyncOperation()

    // Then
    XCTAssertTrue(sut.operationCompleted)
}
```

**For expectations (when async/await isn't available)**:
```swift
func testWithExpectation() {
    // Given
    let expectation = expectation(description: "Operation completes")
    var result: String?

    // When
    sut.performOperation { value in
        result = value
        expectation.fulfill()
    }

    // Then
    waitForExpectations(timeout: 5.0)
    XCTAssertEqual(result, "expected")
}
```

---

## How to Test Protocol Implementations

**Template**:
```swift
import XCTest

@testable import Unmissable

final class [Protocol]ConformanceTests: XCTestCase {

    @MainActor
    func testConformsToProtocol() {
        // Given
        let sut: any [Protocol] = [ConcreteClass]()

        // When
        sut.[protocolMethod]()

        // Then
        XCTAssertTrue(sut.[expectedState])
    }
}
```

---

## Test Data Helpers

**Create test fixtures**:
```swift
extension Event {
    static func testEvent(
        id: String = "test-123",
        title: String = "Test Meeting",
        startDate: Date = Date(),
        endDate: Date = Date().addingTimeInterval(3600)
    ) -> Event {
        Event(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            calendarId: "primary"
        )
    }
}

// Usage in tests:
let event = Event.testEvent(title: "Custom Title")
```

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

## Snapshot Testing

**For UI components** (requires SnapshotTesting dependency):

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

**First run**: Creates reference snapshot in `__Snapshots__/` folder
**Subsequent runs**: Compares against reference

---

## Common Mistakes

**Test setup**:
- Don't create real UI in tests
- Do use `isTestEnvironment: true` for managers
- Don't forget to set `sut = nil` in `tearDown()`
- Do clean up state between tests

**Async testing**:
- Don't use `sleep()` to wait for async operations
- Do use `async/await` or `XCTestExpectation`
- Don't forget `@MainActor` when testing `@MainActor` classes
- Do mark test methods as `async` when needed

**Naming**:
- Don't use vague names: `testMethod1`, `testThing`
- Do use descriptive names: `testExtractLinks_withEmptyString_returnsEmptyArray`

**Assertions**:
- Don't use bare `XCTAssert(condition)` for equality checks
- Do use `XCTAssertEqual(actual, expected)` for better failure messages
- Don't ignore test failures
- Do fix failing tests before committing

**Isolation**:
- Don't rely on test execution order
- Do make each test independent
- Don't share mutable state between tests
- Do reset state in `setUp()` and `tearDown()`

**Coverage**:
- Don't skip edge cases (nil, empty, boundary values)
- Do test happy path AND error paths
- Don't test implementation details
- Do test behavior/outcomes
