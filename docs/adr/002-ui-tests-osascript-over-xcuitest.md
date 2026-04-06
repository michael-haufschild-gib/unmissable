# ADR-002: UI Tests Use osascript Instead of XCUITest

**Status**: Accepted
**Date**: 2026-04-06
**Context**: SwiftUI MenuBarExtra UI testing

## Decision

UI tests for Unmissable use **shell scripts with `osascript` (System Events AppleScript)** instead of XCUITest.

## Context

Unmissable is a macOS menu bar app built with SwiftUI's `MenuBarExtra(.window)`. The primary UI surface is a popover that opens when the user clicks the status item in the system menu bar.

We attempted to test this flow with XCUITest (`XCUIApplication` + `XCTestCase`). After extensive investigation, we found that **XCUITest's synthesised events do not trigger SwiftUI MenuBarExtra's popover handler**:

- XCUITest can locate the `StatusItem` element in the accessibility tree
- XCUITest's `.click()` is delivered to the element
- The MenuBarExtra popover **never opens** — 0 windows appear
- The same click via AppleScript (`click menu bar item 1 of menu bar 2`) opens the popover instantly
- The issue affects **all** XCUITest interactions with the app — not just the status item but also buttons, windows, and menu items are unresponsive to synthesised events
- The app's main thread is **not blocked** (confirmed via `sample` thread dump — idle in the normal AppKit event loop)
- The app works correctly when launched from the command line or via Finder

Additional complications:
- `CGEvent` mouse posting requires accessibility permissions the XCUITest runner process lacks
- `AXUIElementPerformAction` returns `kAXErrorAPIDisabled` (-25211) from the test process
- `NSAppleScript` and `Process`-based `osascript` calls from within XCUITest are silently blocked
- Swift 6 `defaultIsolation(MainActor.self)` conflicts with XCTestCase's `nonisolated` lifecycle methods, requiring per-target build flag overrides

## Approach

UI tests are implemented as bash scripts in `Scripts/` that:

1. **Build** the app via `xcodebuild build`
2. **Launch** the built binary directly as a child process
3. **Interact** via `osascript` (System Events AppleScript)
4. **Assert** by querying element existence and window counts via `osascript`
5. **Clean up** by terminating the app process

This mirrors the real user interaction path — System Events sends the same events as physical mouse clicks.

## Consequences

**Positive**:
- Tests exercise the real click → popover → button → side-effect chain
- No separate XCUITest-runner permission issue — `osascript` reuses the terminal's existing System Events authorization
- No Swift 6 concurrency conflicts — no XCTestCase subclassing needed
- Simple to debug — run the script manually and watch the app respond
- Fast — no xcodebuild test harness overhead

**Negative**:
- No Xcode Test Navigator integration (tests appear as script pass/fail, not individual XCTest cases)
- Requires System Events accessibility permission on the machine running tests
- AppleScript element queries are more fragile than XCUITest's typed element API
- CI requires a GUI session (same as XCUITest)

## Alternatives Considered

| Alternative | Why Rejected |
|---|---|
| XCUITest with `.click()` | Synthesised events don't trigger MenuBarExtra popover |
| XCUITest + CGEvent | Test runner lacks accessibility permissions |
| XCUITest + AXUIElement API | Returns `kAXErrorAPIDisabled` from test process |
| XCUITest + NSAppleScript | Silently blocked in XCUITest sandbox |
| MenuBarExtraAccess library | Adds dependency; still can't fix XCUITest click delivery |
| Distributed notification toggle | Would bypass the real click path; other buttons still unresponsive |
