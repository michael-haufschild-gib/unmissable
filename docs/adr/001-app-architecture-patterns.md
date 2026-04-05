# ADR-001: App Architecture Patterns for a macOS Menu Bar App

**Status**: Accepted
**Date**: 2026-04-05
**Context**: Swift 6.3 / Xcode 26 / macOS 15.0+ / SwiftUI + AppKit hybrid

## Decision

Three interconnected architectural choices govern how Unmissable is structured:

1. **`defaultIsolation(MainActor.self)`** for all targets
2. **NSWindow (via NSHostingController)** for all app windows except the menu bar popover
3. **Hybrid SwiftUI App lifecycle** with `@NSApplicationDelegateAdaptor`

## Context

Unmissable is a macOS menu bar utility (LSUIElement) that displays full-screen blocking overlays, manages preferences/onboarding windows, and runs calendar sync in the background. The architecture must support:

- A menu bar popover (primary UI surface)
- Full-screen overlay windows at `.screenSaver` level across all displays
- On-demand preferences and onboarding windows that must come to the foreground despite `.accessory` activation policy
- Background calendar sync and database operations
- Strict Swift 6 concurrency safety

## Decision 1: `defaultIsolation(MainActor.self)`

### Chosen

All targets use `-default-isolation MainActor` with the companion Approachable Concurrency flags (`NonisolatedNonsendingByDefault`, `InferIsolatedConformances`). Value types and background utilities are explicitly marked `nonisolated`.

### Why

The alternative (nonisolated default + explicit `@MainActor` on managers) produces fewer total annotations (~15-20 `@MainActor` vs ~50+ `nonisolated`), but the failure modes are asymmetric:

| Forgotten annotation | With `defaultIsolation` | Without `defaultIsolation` |
|---------------------|------------------------|---------------------------|
| On a manager class | Impossible (already MainActor) | **Silent data race** — mutations from background threads that SwiftUI won't detect |
| On a value type | **Compile error** — can't pass across isolation boundaries | Impossible (already nonisolated) |

`defaultIsolation` eliminates the dangerous failure mode (silent data race) at the cost of more annotations that catch harmlessly (compile errors). For an app where ~80% of code is UI-bound `@Observable` managers and SwiftUI views, this is the correct default.

Background work is correctly modeled with explicit opt-outs:
- `DatabaseManager` — `actor` (own isolation domain)
- `GoogleCalendarAPIService` parsing — `@concurrent nonisolated` functions
- `FlightRecorder`, `LinkParser` — `nonisolated class: Sendable` with internal synchronization
- All model structs — `nonisolated struct` (no thread affinity)

### Rejected alternatives

- **nonisolated default**: More natural annotation count, but the penalty for forgetting `@MainActor` is a runtime data race, not a compile error. In a project with 15+ manager classes, this is an unacceptable risk.

### Known limitations

- Third-party macros cannot detect `defaultIsolation` (they only see explicit `@MainActor`). Not currently an issue — the project uses no custom macros, and Apple's `@Observable` handles this correctly. Would become relevant if adopting macro-heavy libraries.

### References

- [SE-0466: Control Default Actor Isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)
- [Donny Wals — Should you opt-in to Swift 6.2's Main Actor isolation?](https://www.donnywals.com/should-you-opt-in-to-swift-6-2s-main-actor-isolation/)
- [fatbobman — Default Actor Isolation: New Problems from Good Intentions](https://fatbobman.com/en/posts/default-actor-isolation/)

## Decision 2: NSWindow over SwiftUI Scenes

### Chosen

All app windows (overlays, preferences, onboarding, meeting details popup) are created via `NSWindow` + `NSHostingController`/`NSHostingView`. The only SwiftUI Scene is `MenuBarExtra`.

### Why

**Overlays** require `.screenSaver` window level, borderless style, per-screen instantiation, and programmatic show/hide driven by timer events. No SwiftUI Scene type supports any of these.

**Preferences and onboarding** require bringing a window to the foreground from an LSUIElement app (`.accessory` activation policy). SwiftUI's `Settings` scene and `SettingsLink` are broken in this context — they assume the app is already active with proper window management context. Peter Steinberger's 2025 deep-dive confirms that the workaround (hidden `Window` scene + policy juggling + timing delays) is equally complex as manual `NSWindow` management, with additional fragility (scene ordering matters, silent failures).

**Meeting details popup** requires positioning relative to a parent window, which needs AppKit APIs.

### Rejected alternatives

- **SwiftUI `Settings` scene**: Broken for menu bar apps. `SettingsLink` fails silently. `openSettings` environment action requires an existing SwiftUI render tree that menu bar apps don't have in the right state.
- **SwiftUI `Window` scene + `openWindow`**: Works for showing a window, but still requires activation policy juggling for foreground behavior, and loses fine-grained control over window delegate events, collection behavior, and window level.
- **Hidden Window scene to bootstrap `openSettings`**: Steinberger's approach. Adds a footgun (the hidden Window must be declared before the Settings scene) for no net reduction in complexity.

### Known limitations

- Apple is actively improving SwiftUI Scene APIs. Future macOS versions may fix the menu bar app limitations. The NSWindow approach means maintaining manual window management code that could eventually become unnecessary. With macOS 15.0 as the deployment target, this is a multi-year concern.
- Activation policy switching (`.accessory` <-> `.regular`) is duplicated across `PreferencesWindowManager` and `OnboardingWindowManager`. A reference-counted activation policy coordinator would deduplicate this and prevent bugs if both windows are open simultaneously.

### References

- [Peter Steinberger — Showing Settings from macOS Menu Bar Items: A 5-Hour Journey (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
- [Nil Coalescing — Build a macOS menu bar utility in SwiftUI](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)

## Decision 3: Hybrid SwiftUI App + NSApplicationDelegateAdaptor

### Chosen

The app entry point is `@main struct UnmissableApp: App` with `@NSApplicationDelegateAdaptor(AppDelegate.self)`. The SwiftUI App lifecycle manages the `MenuBarExtra` scene. The `AppDelegate` handles lifecycle events that SwiftUI cannot: activation policy, URL scheme handling, reopen behavior, and termination.

### Why

`MenuBarExtra` is vastly simpler than manual `NSStatusItem` + `NSPopover` management. It provides declarative menu bar content with SwiftUI views, automatic popover sizing, and `.window` style for rich content. The `@NSApplicationDelegateAdaptor` provides the escape hatch for:

- `applicationDidFinishLaunching` — set `.accessory` activation policy (SwiftUI has no API for this)
- `handleURLEvent` — OAuth callback URL scheme handling
- `applicationShouldHandleReopen` — show preferences when Dock icon is clicked with no visible windows
- `applicationShouldTerminate` — controlled shutdown

### Rejected alternatives

- **Pure AppKit** (`NSApplication` subclass + `NSStatusItem`): Loses `MenuBarExtra`'s declarative simplicity. Would require manual `NSPopover` management, manual status item configuration, and manual hosting of SwiftUI views in the popover.
- **Pure SwiftUI App** (no `AppDelegate`): Cannot set activation policy, handle URL schemes, or control reopen behavior. These are required for a menu bar app.

## Consequences

- New windows (e.g., a future "About" panel) should follow the `NSWindow` + `NSHostingController` pattern, not introduce new SwiftUI Scenes.
- New model types must be marked `nonisolated`. New manager classes get `@MainActor` for free via `defaultIsolation`.
- Background work must use `actor`, `@concurrent nonisolated`, or `nonisolated class: Sendable` — never implicitly-MainActor classes doing async work.
- The activation policy coordination gap should be addressed if the app gains more window types.
