# Architecture Guide

**Purpose**: Where to put code and what patterns to follow in Unmissable.
**Tech Stack**: Swift 6.1 with StrictConcurrency | macOS 14.0+ | SwiftUI + AppKit | GRDB.swift | SPM

---

## Where to Put New Code

```text
Sources/Unmissable/
├── App/            # Application lifecycle (AppDelegate, AppState, ServiceContainer)
├── Config/         # Configuration files
├── Core/           # Shared services/managers, design system tokens
├── Features/       # Feature-specific modules (each feature = subfolder)
│   └── [Feature]/  # e.g., Overlay/, CalendarConnect/, FocusMode/
├── Models/         # Data structures (Codable structs, GRDB records)
└── Resources/      # Assets (images, sounds)
```

**Decision tree**:
- New **service/manager**? -> `Sources/Unmissable/Core/[Name]Manager.swift`
- New **feature**? -> `Sources/Unmissable/Features/[FeatureName]/` (manager + views)
- New **data model**? -> `Sources/Unmissable/Models/[Name].swift`
- New **protocol**? -> `Sources/Unmissable/Core/Protocols.swift` (or feature-specific if isolated)
- New **design token**? -> `Sources/Unmissable/Core/DesignTokens.swift`
- New **UI component**? -> `Sources/Unmissable/Core/Styles.swift` (buttons, toggles, badges)
- New **UI container**? -> `Sources/Unmissable/Core/Containers.swift` (cards, sections, pickers)
- New **test**? -> `Tests/UnmissableTests/[Name]Tests.swift`

---

## File Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Class/Struct | PascalCase matching content | `EventScheduler.swift` |
| Protocol | PascalCase + `-ing` suffix | `OverlayManaging`, `CalendarAPIProviding` |
| Manager class | `[Domain]Manager` | `DatabaseManager`, `SyncManager` |
| View file | `[Name]View.swift` | `OverlayContentView.swift` |
| Test file | `[ClassName]Tests.swift` | `EventTests.swift`, `LinkParserTests.swift` |

---

## Design System

All UI in `Sources/` must use design tokens. Raw values are **lint errors**.

### Token Structure

Access via `@Environment(\.design) var design` after applying `.themed(themeManager)`:

| Token Group | Access | Example |
|-------------|--------|---------|
| Colors | `design.colors.*` | `design.colors.textPrimary`, `design.colors.accent` |
| Fonts | `design.fonts.*` | `design.fonts.headline`, `design.fonts.body` |
| Spacing | `design.spacing.*` | `design.spacing.md`, `design.spacing.lg` |
| Corners | `design.corners.*` | `design.corners.md`, `design.corners.lg` |
| Shadows | `design.shadows.*` | `design.shadows.soft`, `design.shadows.glow` |
| Animations | `DesignAnimations.*` | `DesignAnimations.press`, `DesignAnimations.hover` |

### UI Components (UM* prefix)

| Component | File | Usage |
|-----------|------|-------|
| `UMButtonStyle` | `Styles.swift` | `.buttonStyle(UMButtonStyle(.primary))` |
| `UMToggleStyle` | `Styles.swift` | `.toggleStyle(UMToggleStyle())` |
| `UMStatusIndicator` | `Styles.swift` | `UMStatusIndicator(.success)` |
| `UMBadge` | `Styles.swift` | `UMBadge("New", variant: .accent)` |
| `.umCard()` | `Containers.swift` | View modifier for card styling |
| `.umGlass()` | `Containers.swift` | View modifier for glass effect |
| `UMSection` | `Containers.swift` | `UMSection("Title", icon: "gear") { ... }` |
| `.umPickerStyle()` | `Containers.swift` | View modifier for picker styling |

All token usage is lint-enforced. See `docs/meta/styleguide.md` for the full list of banned patterns.

---

## How to Create a New Model

**Location**: `Sources/Unmissable/Models/[Name].swift`

```swift
import Foundation

struct [Name]: Identifiable, Codable, Equatable {
    let id: String
    // Add properties

    init(id: String) {
        self.id = id
    }
}
```

---

## How to Create a New Service/Manager

**Location**: `Sources/Unmissable/Core/[Name]Manager.swift`

```swift
import Foundation
import OSLog

@MainActor
class [Name]Manager: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "[Name]Manager")

    @Published private(set) var someState: [Type] = [default]

    private let dependency: DependencyType

    init(dependency: DependencyType) {
        self.dependency = dependency
    }

    func doSomething() {
        logger.info("Doing something")
    }
}
```

**Then**: Register in `ServiceContainer.swift` and inject via initializer.

---

## How to Create a New Feature Module

**Location**: `Sources/Unmissable/Features/[FeatureName]/`

```text
Features/[FeatureName]/
├── [FeatureName]Manager.swift   # Business logic
├── [FeatureName]View.swift      # SwiftUI view (if needed)
└── [FeatureName]Trigger.swift   # Event triggers (if needed)
```

Wire up to `AppState` or relevant coordinator after creation.

---

## Key Patterns

### Protocol-Based Dependency Injection

```swift
// Protocol in Protocols.swift
@MainActor
protocol OverlayManaging: ObservableObject {
    var activeEvent: Event? { get }
    func showOverlay(for event: Event)
}

// Production implementation
class OverlayManager: OverlayManaging { ... }

// Test-safe implementation
class TestSafeOverlayManager: OverlayManaging { ... }

// Factory pattern
enum OverlayManagerFactory {
    @MainActor
    static func create(isTestEnvironment: Bool) -> any OverlayManaging {
        isTestEnvironment ? TestSafeOverlayManager() : OverlayManager()
    }
}
```

### ServiceContainer (DI Root)

All services are created in `ServiceContainer` and passed to consumers. No singletons.

```swift
final class ServiceContainer {
    let databaseManager: DatabaseManager
    let linkParser: LinkParser
    let themeManager: ThemeManager
    let overlayManager: any OverlayManaging
    // ...
    init(...) { /* wire dependencies */ }
}
```

### @MainActor for UI Code

Always use `@MainActor` for classes that modify UI state, protocols that touch UI, and methods called from SwiftUI views.

### Async/Await for Concurrency

Use `async/await` for all new async code. No completion handlers.

---

## Common Mistakes

**File placement**:
- Don't put models in `Core/`. Do put them in `Models/`.
- Don't put feature-specific code in `Core/`. Do create a folder in `Features/`.

**Design system**:
- Don't use raw `Color(red:)` or `.system(size:)`. Do use `design.colors.*` and `design.fonts.*`.
- Don't use `PlainButtonStyle`. Do use `UMButtonStyle`.
- Don't use `.cornerRadius(N)`. Do use `.clipShape(RoundedRectangle(...))`.
- Don't use legacy `Custom*` types. Do use `UM*` equivalents.

**Concurrency**:
- Don't access UI from background threads. Do use `@MainActor`.
- Don't use completion handlers for new async code. Do use `async/await`.

**Dependencies**:
- Don't hardcode dependencies. Do inject via initializer or protocol.
- Don't create real managers in tests. Do use `isTestEnvironment: true`.

**Logging**:
- Don't use `print()`. Do use `OSLog` with subsystem `com.unmissable.app`.
- Don't log PII. Do redact sensitive data.

## On-Demand References

| Domain | Serena Memory |
|--------|---------------|
| Detailed folder map | `codebase_structure` |
| Design system patterns | `design_system_patterns` |
| Code style conventions | `style_conventions` |
