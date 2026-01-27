# Architecture Guide for LLM Coding Agents

**Purpose**: Instructions for where to put code and what patterns to follow in Unmissable.
**Tech Stack**: Swift 6.0 with StrictConcurrency | macOS 14.0+ | SwiftUI + AppKit | GRDB.swift | Swift Package Manager

---

## Where to Put New Code

```
Sources/Unmissable/
├── App/            # PUT application lifecycle code HERE (AppDelegate, main entry)
├── Config/         # PUT configuration files HERE
├── Core/           # PUT shared services/managers HERE (business logic)
├── Features/       # PUT feature-specific modules HERE (each feature = subfolder)
│   └── [Feature]/  # e.g., Overlay/, CalendarConnect/, FocusMode/
├── Models/         # PUT data structures HERE (Codable structs, GRDB records)
└── Resources/      # PUT assets HERE (images, sounds)
```

**Decision tree**:
- Creating a new **service/manager**? → Put in `Sources/Unmissable/Core/`, name it `[Name]Manager.swift` or `[Name].swift`
- Creating a new **feature**? → Create folder `Sources/Unmissable/Features/[FeatureName]/`, add views and logic there
- Creating a new **data model**? → Put in `Sources/Unmissable/Models/[Name].swift`
- Creating a new **protocol**? → Put in `Sources/Unmissable/Core/Protocols.swift` (or feature-specific if isolated)
- Creating a **test**? → Put in `Tests/UnmissableTests/[Name]Tests.swift`

---

## File Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Class/Struct | PascalCase matching content | `EventScheduler.swift` |
| Protocol | PascalCase + `-ing` suffix | `OverlayManaging`, `EventScheduling` |
| Manager class | `[Domain]Manager` | `DatabaseManager`, `SyncManager` |
| View file | `[Name]View.swift` | `OverlayContentView.swift` |
| Test file | `[ClassName]Tests.swift` | `EventTests.swift`, `LinkParserTests.swift` |

---

## How to Create a New Model

**Location**: `Sources/Unmissable/Models/[Name].swift`

**Template**:
```swift
import Foundation

struct [Name]: Identifiable, Codable, Equatable {
    let id: String
    // Add properties here

    init(
        id: String,
        // Add parameters here
    ) {
        self.id = id
        // Assign properties
    }
}
```

**Steps**:
1. Create file at `Sources/Unmissable/Models/[Name].swift`
2. Copy template above
3. Add properties with `let` for immutable, `var` for mutable
4. Implement `Equatable` if needed for comparisons
5. Add computed properties for derived values

---

## How to Create a New Service/Manager

**Location**: `Sources/Unmissable/Core/[Name]Manager.swift`

**Template**:
```swift
import Foundation
import OSLog

@MainActor
class [Name]Manager: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "[Name]Manager")

    // Published state
    @Published private(set) var someState: [Type] = [default]

    // Dependencies
    private let dependency: DependencyType

    init(dependency: DependencyType) {
        self.dependency = dependency
    }

    // MARK: - Public Methods

    func doSomething() {
        logger.info("Doing something")
        // Implementation
    }

    // MARK: - Private Methods

    private func helperMethod() {
        // Implementation
    }
}
```

**Steps**:
1. Create file at `Sources/Unmissable/Core/[Name]Manager.swift`
2. Add `@MainActor` if it touches UI or must run on main thread
3. Use `OSLog` for logging (subsystem: `com.unmissable.app`)
4. Make class `ObservableObject` if SwiftUI views need to observe it
5. Use `@Published` for observable state

---

## How to Create a New Protocol

**Location**: `Sources/Unmissable/Core/Protocols.swift` (or feature-specific file)

**Template**:
```swift
/// Protocol for [description] functionality
@MainActor
protocol [Name]Managing: ObservableObject {
    var someProperty: PropertyType { get }

    func doAction()
    func performAsync() async
}
```

**Naming rules**:
- Use `-Managing` suffix for manager protocols: `OverlayManaging`, `EventScheduling`
- Use `-ing` suffix for capability protocols: `SoundManaging`, `FocusModeManaging`
- Add `@MainActor` if protocol methods touch UI

---

## How to Create a New Feature Module

**Location**: `Sources/Unmissable/Features/[FeatureName]/`

**Structure**:
```
Features/
└── [FeatureName]/
    ├── [FeatureName]Manager.swift   # Business logic
    ├── [FeatureName]View.swift      # SwiftUI view (if needed)
    └── [FeatureName]Trigger.swift   # Event triggers (if needed)
```

**Steps**:
1. Create folder `Sources/Unmissable/Features/[FeatureName]/`
2. Create manager class for business logic
3. Create SwiftUI views if UI is needed
4. Wire up to `AppState` or relevant coordinator

---

## Key Patterns to Follow

### 1. Protocol-Based Dependency Injection

```swift
// Define protocol
@MainActor
protocol OverlayManaging: ObservableObject {
    func showOverlay(for event: Event)
}

// Production implementation
class OverlayManager: OverlayManaging {
    func showOverlay(for event: Event) { /* real UI */ }
}

// Test implementation
class TestSafeOverlayManager: OverlayManaging {
    func showOverlay(for event: Event) { /* no UI, just state */ }
}

// Factory for creating appropriate implementation
enum OverlayManagerFactory {
    @MainActor
    static func create(isTestEnvironment: Bool) -> any OverlayManaging {
        if isTestEnvironment {
            return TestSafeOverlayManager()
        } else {
            return OverlayManager()
        }
    }
}
```

### 2. Singleton for Stateless Utilities

```swift
class LinkParser {
    static let shared = LinkParser()

    private init() {}

    func extractLinks(from text: String) -> [URL] {
        // Implementation
    }
}
```

### 3. @MainActor for UI Code

Always use `@MainActor` for:
- Classes that modify UI state
- Protocols that touch UI
- Methods called from SwiftUI views

```swift
@MainActor
class SomeUIManager: ObservableObject {
    @Published var isVisible = false

    func updateUI() {
        isVisible = true  // Safe - guaranteed main thread
    }
}
```

### 4. Async/Await for Concurrency

```swift
func startScheduling(events: [Event]) async {
    for event in events {
        await scheduleEvent(event)
    }
}
```

---

## Code Style Requirements

**Formatting** (enforced by `.swiftformat`):
- Indent: 4 spaces
- Max line width: 120 characters
- Line breaks: LF
- Commas: always trailing
- Semicolons: never

**Linting** (enforced by `.swiftlint.yml`):
- Function body: max 50 lines (warning), 100 (error)
- Type body: max 200 lines (warning), 300 (error)
- Cyclomatic complexity: max 10 (warning), 20 (error)

**Run before committing**:
```bash
./Scripts/format.sh
```

---

## Common Mistakes

**File placement**:
- Don't put models in `Core/`
- Do put models in `Models/`
- Don't put feature-specific code in `Core/`
- Do create a folder in `Features/` for new features

**Naming**:
- Don't use lowercase for type names: `eventScheduler.swift`
- Do use PascalCase: `EventScheduler.swift`
- Don't use generic names: `Manager.swift`, `Helper.swift`
- Do use domain-specific names: `DatabaseManager.swift`, `LinkParser.swift`

**Concurrency**:
- Don't access UI from background threads
- Do use `@MainActor` for UI-related code
- Don't use completion handlers for new async code
- Do use `async/await`

**Dependencies**:
- Don't hardcode dependencies in classes
- Do inject via initializer or protocol
- Don't create test-unsafe managers in tests
- Do use `isTestEnvironment: true` factory parameter

**Logging**:
- Don't use `print()` in production code
- Do use `OSLog` with appropriate category
- Don't log PII (emails, names)
- Do redact sensitive data in logs
