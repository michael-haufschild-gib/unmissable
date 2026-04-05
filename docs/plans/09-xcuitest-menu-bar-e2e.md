# Plan 09: XCUITest Menu Bar E2E Infrastructure

## Problem

Unmissable's primary user interaction is through a macOS menu bar icon. Users click it, a popover window appears with events/controls, and they interact with buttons (Preferences, Quit, Sync, event rows, Join). None of this is E2E tested. Existing tests cover:

- **Data layer** (MenuBarE2ETests): MenuBarPreviewManager state, EventGrouping, CalendarService properties
- **Visual rendering** (MenuBarSnapshotTests): snapshot images of MenuBarView/MenuBarLabelView
- **Popup internals** (MeetingDetailsE2ETests): popup manager show/hide via TestSafe doubles

What's untested: clicking the icon, the popover appearing, interacting with buttons inside it, and verifying side effects (preferences window opens, meeting details show, sync triggers).

## Solution

Add MenuBarExtraAccess library + XCUITest infrastructure to write real E2E tests that click the menu bar icon and interact with the popover like a user would.

---

## Current Architecture (read this first)

### App Entry Point

**`Sources/Unmissable/App/UnmissableApp.swift`**:
```swift
@main
struct UnmissableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(appState.calendar)
                .themed(themeManager: appState.themeManager)
        } label: {
            MenuBarLabelView()
                .environment(appState.menuBarPreview)
        }
        .menuBarExtraStyle(.window)  // <-- WINDOW style, not menu
    }
}
```

Key facts:
- `.menuBarExtraStyle(.window)` means the popup is an **NSWindow/popover**, NOT an NSMenu
- XCUITest queries use `app.windows`, not `app.menus`
- `MenuBarLabelView` shows either a `calendar.badge.clock` icon or countdown text

### AppDelegate

**`Sources/Unmissable/App/AppDelegate.swift`**:
- Line 14: `NSApp.setActivationPolicy(.accessory)` — hides dock icon
- Handles OAuth URL callbacks
- `LSUIElement = true` in `Info.plist` (line 32)

### Menu Bar Popup Content

**`Sources/Unmissable/App/MenuBarView.swift`** — the popover content:
- Width: 340pt (line 6)
- Structure: `headerSection` → `contentSection` → `footerSection`
- Footer has "Preferences" button and "Quit" button
- Connected state shows: sync status bar, events list, sync button
- Disconnected state shows: connect Apple/Google calendar buttons
- Database error shows: error card with retry button

**Existing accessibility identifiers** (all in MenuBarView.swift):
| Identifier | Element | Line |
|---|---|---|
| `menu-bar-view` | Root VStack | 48 |
| `retry-database-button` | DB error retry | 134 |
| `preferences-button` | Footer Preferences | 160 |
| `quit-button` | Footer Quit | 168 |
| `connect-apple-calendar-button` | Apple Calendar connect | 218 |
| `connect-google-calendar-button` | Google Calendar connect | 226 |
| `sync-status-text` | Sync status label | 246 |
| `sync-button` | Manual sync trigger | 260 |
| `no-events-text` | Empty state message | 277 |
| `more-events-indicator` | "N more events" | 334 |
| `event-row-{id}` | Individual event row | EventRow.swift:154 |

### Action Chains (what buttons do)

| User Action | Code Path |
|---|---|
| Tap "Preferences" | `AppState.showPreferences()` → `PreferencesWindowManager.showPreferences()` → creates NSWindow |
| Tap "Quit" | `NSApplication.shared.terminate(nil)` |
| Tap event row | `AppState.showMeetingDetails(for:)` → `MeetingDetailsPopupManager.showPopup()` → creates popup NSWindow |
| Tap "Sync" | `Task { await appState.syncNow() }` |
| Tap "Join" (on event) | `NSWorkspace.shared.open(primaryLink)` |
| Tap connect buttons | Triggers calendar connect flow |

### Build System

- **SPM-only** — no `.xcodeproj` or `.xcworkspace` exists
- `Package.swift`: swift-tools-version 6.3, macOS 14.0+
- Build: `swift build`
- Tests: `./Scripts/test.sh` (wraps `swift test` with worker limits, timeouts)
- Release: `./Scripts/build-release.sh` (SPM build → manual .app bundle creation)
- Swift 6.3 strict concurrency with `defaultIsolation(MainActor.self)`
- ApproachableConcurrency flags: `InferIsolatedConformances`, `NonisolatedNonsendingByDefault`

### Existing Test Targets (in Package.swift)

| Target | Path | Dependencies |
|---|---|---|
| `UnmissableTests` | Tests/UnmissableTests/ | Unmissable, TestSupport, SnapshotTesting |
| `IntegrationTests` | Tests/IntegrationTests/ | Unmissable |
| `SnapshotTests` | Tests/SnapshotTests/ | Unmissable, TestSupport, SnapshotTesting |
| `E2ETests` | Tests/E2ETests/ | Unmissable, TestSupport |
| `TestSupport` (library) | Tests/TestSupport/ | Unmissable, Clocks, ConcurrencyExtras |

### Key Test Infrastructure

**`Tests/TestSupport/TestSupport.swift`** provides:
- `TestMenuBarEnvironment` — creates AppState + CalendarService + managers for testing MenuBarView
- `TestSafeOverlayManager` — stub that doesn't create real fullscreen overlays
- `TestSafeLoginItemManager` — stub for login item management
- `TestSafeMeetingDetailsPopupManager` — records calls without real windows
- `TestSafeNotificationManager` — captures sent notifications
- `TestClock` — deterministic time control
- `findAccessibilityElement(identifier:in:)` — recursive NSView accessibility lookup (added this session, needs `@MainActor`)

**`Tests/E2ETests/E2ETestEnvironment.swift`** provides:
- Full environment with real DatabaseManager, EventScheduler, etc.
- `E2EEventBuilder` — factory methods for test events
- `seedEvents()`, `fetchUpcomingEvents()`, etc.

### Existing Changes in Working Tree

These changes were made earlier in this session and are uncommitted:

1. **`PreferencesWindowManager.swift`**: Added `isWindowVisible`, `windowTitle` computed properties, `close()` method, and `setActivationPolicy(.regular/.accessory)` lifecycle (matching OnboardingWindowManager pattern). **Keep these** — they're independently useful.

2. **`AppState.swift`**: Changed `preferencesWindowManager` from `private` to `private(set)`, added `isTestEnvironment` parameter to init, added `observeAppLaunch()` to defer `checkInitialState()` until after `didFinishLaunchingNotification`. **Keep these**.

3. **`TestSupport.swift`**: Added `findAccessibilityElement(identifier:in:)` helper with `@MainActor`. **Keep this**.

4. **`Tests/E2ETests/MenuBarEntryPointE2ETests.swift`**: New file with XCTest-based tests. **Delete this** — it will be replaced by proper XCUITest tests.

---

## Implementation Steps

### Step 1: Add MenuBarExtraAccess Dependency

**File: `Package.swift`**

Add to `dependencies` array:
```swift
.package(url: "https://github.com/orchetect/MenuBarExtraAccess.git", from: "1.3.0"),
```

Add to `Unmissable` target dependencies:
```swift
.product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
```

### Step 2: Integrate MenuBarExtraAccess into UnmissableApp

**File: `Sources/Unmissable/App/UnmissableApp.swift`**

Transform from:
```swift
@main
struct UnmissableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(appState.calendar)
                .themed(themeManager: appState.themeManager)
        } label: {
            MenuBarLabelView()
                .environment(appState.menuBarPreview)
        }
        .menuBarExtraStyle(.window)
    }
}
```

To:
```swift
import MenuBarExtraAccess

@main
struct UnmissableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var isMenuPresented = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(appState.calendar)
                .themed(themeManager: appState.themeManager)
                .introspectMenuBarExtraWindow { window in
                    window.accessibilityIdentifier = "unmissable-popover"
                }
        } label: {
            MenuBarLabelView()
                .environment(appState.menuBarPreview)
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented) { statusItem in
            statusItem.button?.accessibilityIdentifier = "unmissable-status-item"
        }
        .menuBarExtraStyle(.window)
    }
}
```

Key additions:
- `import MenuBarExtraAccess`
- `@State private var isMenuPresented = false`
- `.menuBarExtraAccess(isPresented:) { statusItem in }` — sets accessibility identifier on the NSStatusItem button
- `.introspectMenuBarExtraWindow { window in }` — sets accessibility identifier on the popover window

### Step 3: Create Xcode Project for UI Testing

XCUITest requires an Xcode project with a UI Testing Bundle target. SPM packages can be opened in Xcode directly (`open Package.swift`), but UI test targets must be added through an `.xcodeproj`.

**Option A (recommended): Generate project from SPM**

```bash
# Xcode can open Package.swift directly and create a workspace
xcodebuild -list -workspace .  # See what Xcode infers

# Or create a minimal .xcodeproj that wraps the SPM package
# This is done through Xcode: File > New > Project > select "UI Testing Bundle"
```

**Option B: Minimal Xcode project alongside SPM**

Create `Unmissable.xcodeproj` that:
1. References the SPM `Package.swift` for the main app target
2. Adds a `UnmissableUITests` UI Testing Bundle target
3. Sets the test target's "Target Application" to `Unmissable`

**The practical approach:**

1. Open the project in Xcode: `open Package.swift`
2. Xcode creates an implicit workspace from the SPM package
3. In Xcode: File → New → Target → macOS → UI Testing Bundle
4. Name it `UnmissableUITests`
5. Set "Target Application" to `Unmissable`
6. This creates the `.xcodeproj` with the UI test target
7. The UI test target's source goes in `Tests/UITests/`

**Important**: After creating the Xcode project, add it to `.gitignore` patterns appropriately OR commit it. The SPM `Package.swift` remains the source of truth for the app and unit test targets; the Xcode project is only needed for the UI test target.

### Step 4: Handle LSUIElement for UI Tests

**File: `Sources/Unmissable/App/AppDelegate.swift`**

The app has `LSUIElement = true` in Info.plist and calls `NSApp.setActivationPolicy(.accessory)` in `applicationDidFinishLaunching`. XCUITest needs the app to be launchable.

Add UI test detection:
```swift
func applicationDidFinishLaunching(_: Notification) {
    logger.info("Unmissable app finished launching")

    // When running under UI tests, skip accessory policy so XCUITest
    // can discover and interact with the app
    if ProcessInfo.processInfo.arguments.contains("--uitesting") {
        logger.info("UI testing mode — skipping .accessory activation policy")
    } else {
        NSApp.setActivationPolicy(.accessory)
    }

    // ... rest unchanged
}
```

### Step 5: Run Discovery Spike

Before writing tests, run a spike to discover the accessibility tree. Create a minimal test:

**File: `Tests/UITests/MenuBarDiscoveryTests.swift`**

```swift
import XCTest

final class MenuBarDiscoveryTests: XCTestCase {
    func testDiscoverAccessibilityTree() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // Wait for app to settle
        sleep(3)

        // Print the entire accessibility tree — look for the status item
        print("=== APP TREE ===")
        print(app.debugDescription)

        // Try common queries for the status item
        let byIdentifier = app.buttons["unmissable-status-item"]
        print("By identifier exists: \(byIdentifier.exists)")

        let menuBarButtons = app.menuBars.buttons
        print("Menu bar buttons count: \(menuBarButtons.count)")
        for i in 0..<menuBarButtons.count {
            let btn = menuBarButtons.element(boundBy: i)
            print("  Button \(i): \(btn.identifier) / \(btn.label)")
        }

        // Try status items query
        let statusItems = app.statusItems
        print("Status items count: \(statusItems.count)")

        // If the status item is found and tapped, look for the popover window
        if byIdentifier.exists {
            byIdentifier.tap()
            sleep(1)
            print("=== AFTER TAP ===")
            print(app.debugDescription)
        }
    }
}
```

**Run this spike FIRST.** The output tells you:
- Where the status item lives in the accessibility tree
- The correct query to find it
- What the popover window looks like after tapping
- Whether `accessibilityIdentifier` propagates through MenuBarExtraAccess

**If the status item is NOT found through `app.buttons`**, try:
```swift
// Query system UI server for status items
let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
let statusItem = systemUI.buttons["unmissable-status-item"]
```

### Step 6: Write the E2E Tests

**File: `Tests/UITests/MenuBarE2EUITests.swift`**

Based on spike results, write tests for each user interaction:

```swift
import XCTest

final class MenuBarE2EUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // Wait for status item to appear
        // NOTE: Adjust the query based on spike results
        let statusItem = app.buttons["unmissable-status-item"]
        XCTAssertTrue(
            statusItem.waitForExistence(timeout: 5),
            "Status item should appear in menu bar"
        )
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Status Item Presence

    func testStatusItem_existsInMenuBar() {
        let statusItem = app.buttons["unmissable-status-item"]
        XCTAssertTrue(statusItem.exists)
    }

    // MARK: - Popover Opens/Closes

    func testStatusItem_tap_opensPopover() {
        app.buttons["unmissable-status-item"].tap()

        let popover = app.windows["unmissable-popover"]
        XCTAssertTrue(
            popover.waitForExistence(timeout: 3),
            "Popover window should appear after tapping status item"
        )
    }

    func testPopover_containsMenuBarView() {
        app.buttons["unmissable-status-item"].tap()

        let popover = app.windows["unmissable-popover"]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        // Verify root accessibility identifier
        XCTAssertTrue(popover.otherElements["menu-bar-view"].exists)
    }

    // MARK: - Footer Buttons

    func testPopover_preferencesButton_opensPreferencesWindow() {
        app.buttons["unmissable-status-item"].tap()
        let popover = app.windows["unmissable-popover"]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        popover.buttons["preferences-button"].tap()

        let prefsWindow = app.windows["Unmissable Preferences"]
        XCTAssertTrue(
            prefsWindow.waitForExistence(timeout: 3),
            "Preferences window should open after tapping Preferences"
        )
    }

    func testPopover_quitButton_exists() {
        app.buttons["unmissable-status-item"].tap()
        let popover = app.windows["unmissable-popover"]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        // Don't actually tap Quit — it terminates the app
        XCTAssertTrue(popover.buttons["quit-button"].exists)
    }

    // MARK: - Disconnected State (first launch, no calendars)

    func testPopover_disconnected_showsConnectButtons() {
        app.buttons["unmissable-status-item"].tap()
        let popover = app.windows["unmissable-popover"]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        // On first launch with no calendars connected
        XCTAssertTrue(
            popover.buttons["connect-apple-calendar-button"].exists ||
            popover.buttons["connect-google-calendar-button"].exists,
            "Should show calendar connect buttons when disconnected"
        )
    }

    // MARK: - Sync Controls (when connected)
    // NOTE: These tests need a connected calendar state.
    // You may need launch arguments to seed test data.

    func testPopover_connected_showsSyncButton() {
        // This test may need "--seed-test-data" launch argument
        // and corresponding AppDelegate logic to pre-populate
        app.buttons["unmissable-status-item"].tap()
        let popover = app.windows["unmissable-popover"]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        // Only valid when calendar is connected
        if popover.buttons["sync-button"].exists {
            XCTAssertTrue(popover.staticTexts["sync-status-text"].exists)
        }
    }
}
```

**Important caveats in the test code:**
- The exact XCUIElement queries (`.buttons`, `.windows`, `.otherElements`) depend on spike results
- First-launch state will be "disconnected" (no calendars) — this is actually useful for testing
- Connected state tests may need launch arguments to seed data
- Some tests need adjustment based on whether the popover auto-closes on button tap

### Step 7: Update CI/Scripts

**File: `Scripts/test.sh`** — no changes needed. Continue using `swift test` for existing targets.

**New file: `Scripts/test-ui.sh`**:
```bash
#!/bin/bash
# Run XCUITest UI tests via xcodebuild
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "Running UI tests..."
xcodebuild test \
    -project Unmissable.xcodeproj \
    -scheme UnmissableUITests \
    -destination "platform=macOS" \
    -resultBundlePath test-reports/ui-tests.xcresult \
    2>&1

echo "UI tests complete."
```

Update `Scripts/build.sh` to optionally include UI tests.

### Step 8: Delete Superseded File

Remove `Tests/E2ETests/MenuBarEntryPointE2ETests.swift` (created earlier this session, superseded by XCUITest approach).

---

## File Changes Summary

| File | Action | Description |
|---|---|---|
| `Package.swift` | Edit | Add MenuBarExtraAccess dependency |
| `Sources/Unmissable/App/UnmissableApp.swift` | Edit | Integrate MenuBarExtraAccess, add accessibility identifiers |
| `Sources/Unmissable/App/AppDelegate.swift` | Edit | Add `--uitesting` launch argument guard |
| `Unmissable.xcodeproj` | Create | Xcode project with UI test target (via Xcode GUI) |
| `Tests/UITests/MenuBarDiscoveryTests.swift` | Create | Spike test to discover accessibility tree |
| `Tests/UITests/MenuBarE2EUITests.swift` | Create | Real E2E tests |
| `Scripts/test-ui.sh` | Create | xcodebuild test runner for UI tests |
| `Tests/E2ETests/MenuBarEntryPointE2ETests.swift` | Delete | Superseded by XCUITest |

### Files Changed Earlier This Session (keep as-is)

| File | Changes |
|---|---|
| `Sources/Unmissable/Features/Preferences/PreferencesWindowManager.swift` | Added `isWindowVisible`, `windowTitle`, `close()`, activation policy lifecycle |
| `Sources/Unmissable/App/AppState.swift` | `preferencesWindowManager` → `private(set)`, `isTestEnvironment` param, `observeAppLaunch()` |
| `Tests/TestSupport/TestSupport.swift` | Added `@MainActor findAccessibilityElement(identifier:in:)` |

---

## Risk: Status Item Discoverability

The biggest unknown is whether XCUITest can find the `NSStatusItem` button. Three possibilities:

1. **Works directly**: `app.buttons["unmissable-status-item"]` finds it. Best case.
2. **Needs SystemUIServer query**: `XCUIApplication(bundleIdentifier: "com.apple.systemuiserver").buttons[...]`. Works but adds a dependency on system UI internals.
3. **Not discoverable via XCUITest at all**: Fall back to `NSStatusItem.button?.performClick(nil)` in integration tests (not true XCUITest but still exercises the real UI).

**Step 5 (discovery spike) resolves this before investing in full test implementation.**

## Verification

1. `swift build` succeeds with MenuBarExtraAccess
2. Existing `./Scripts/test.sh` still passes (no regressions)
3. Discovery spike prints the accessibility tree and identifies the status item query
4. UI tests launch the app, click the icon, verify the popover opens
5. UI tests interact with at least: Preferences button (opens window), Quit button (exists), connect buttons (exist in disconnected state)
