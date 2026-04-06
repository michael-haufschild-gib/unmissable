# ADR-003: Lazy AppState Initialization via .task

**Status**: Accepted
**Date**: 2026-04-06
**Context**: macOS menu bar app lifecycle and activation policy timing

## Decision

`AppState` is initialized **lazily** inside a SwiftUI `.task` modifier on the `MenuBarExtra` label view — not eagerly as a `@State` property initializer.

```swift
// CORRECT — lazy init in .task
@State private var appState: AppState?

// In body:
MenuBarLabelView(menuBarPreview: appState?.menuBarPreview)
    .task {
        if appState == nil {
            appState = AppState(isTestEnvironment: AppRuntime.isRunningTests)
        }
    }
```

```swift
// WRONG — eager init blocks menu bar clicks
@State private var appState = AppState(isTestEnvironment: AppRuntime.isRunningTests)
```

## Context

Unmissable is an `LSUIElement` (menu-bar-only) app. It uses `NSApp.setActivationPolicy(.accessory)` during `applicationDidFinishLaunching` to hide the Dock icon and operate purely from the system menu bar. Interactive windows (Preferences, Onboarding) temporarily acquire `.regular` policy via `ActivationPolicyManager`.

### The init order problem

`@State` property initializers in the `@main` App struct run **before** `applicationDidFinishLaunching`. The execution order is:

1. Swift runtime creates `UnmissableApp` → `@State` property initializers fire
2. `AppState.init()` → creates `ServiceContainer` → creates `OverlayManager`, `ActivationPolicyManager`, etc.
3. `ServiceContainer.init()` triggers `OverlayManager.init()` which interacts with `NSApp`
4. `applicationDidFinishLaunching` fires → `NSApp.setActivationPolicy(.accessory)`

When `AppState` is initialized eagerly (step 1–3), the service graph construction races with AppKit's own startup sequence. Specifically:

- `OverlayManager` creates `NSWindow` instances during init, which implicitly touches `NSApp` state before the activation policy is set
- The `ActivationPolicyManager` reference count starts at 0 (correct), but the windows created during eager init register with the window server before the `.accessory` policy takes effect
- On macOS 15+, this causes the system to treat the app as having a stale activation state — the `MenuBarExtra` status item **receives click events but the popover never opens**

### Why .task works

SwiftUI's `.task` modifier runs **after** the view appears, which is after `applicationDidFinishLaunching` has completed and the activation policy is correctly set to `.accessory`. By deferring `AppState` creation to this point:

- The activation policy is already `.accessory` when `ServiceContainer` creates its window-touching services
- No implicit `NSApp` state is mutated before AppKit is ready
- The `MenuBarExtra` popover handler works correctly

### The dual-path safety mechanism

Because `.task` fires after view appearance, `applicationDidFinishLaunching` has already posted its notification by the time `AppState.init()` subscribes. `AppState.observeAppLaunch()` handles both timing scenarios:

1. **Notification subscription** — catches the case where init runs before the notification
2. **`DispatchQueue.main.async` fallback** — catches the case where the notification already fired
3. **`didCheckInitialState` guard** — ensures `checkInitialState()` runs exactly once regardless of which path wins

## Consequences

**Positive**:
- Menu bar clicks work reliably on all macOS versions
- No race between service graph construction and AppKit lifecycle
- Clean separation: AppKit owns activation policy, SwiftUI owns view lifecycle

**Negative**:
- Brief "Loading..." text appears in the popover if opened during the first frame
- `appState` is optional, adding `if let` / `?.` unwrapping throughout `UnmissableApp.body`
- `MenuBarLabelView.menuBarPreview` must be optional since `appState` may be nil on first render

**Rejected alternative**: Eager init with deferred service construction (splitting `ServiceContainer` into a two-phase init). This was considered but rejected because it would spread the timing constraint across multiple types instead of containing it in one place (`UnmissableApp.task`).

## References

- `Sources/Unmissable/App/UnmissableApp.swift` — lazy init site with explanatory comment
- `Sources/Unmissable/App/AppDelegate.swift:35` — `.accessory` policy set in `applicationDidFinishLaunching`
- `Sources/Unmissable/Core/ActivationPolicyManager.swift` — ref-counted policy coordinator
- `Sources/Unmissable/App/AppState.swift:97` — `observeAppLaunch()` dual-path mechanism
