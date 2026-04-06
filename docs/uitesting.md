# UI Testing Guide

UI tests use `Scripts/test-ui.sh` — a bash script that launches the app as a normal process and interacts via `osascript` (System Events AppleScript). XCUITest is **not used** because its synthesised events don't trigger mouse clicks correctly.

## Running

```bash
./Scripts/test-ui.sh              # all UI tests
./Scripts/test-ui.sh --build      # build first, then test
./Scripts/test-ui.sh test_name    # single test by function name
```

## Architecture

1. **Launch** the built binary directly (`$APP_PATH/Contents/MacOS/Unmissable`)
2. **Interact** via `osascript` wrapping System Events AppleScript
3. **Assert** by querying window counts, element existence, text values
4. **Cleanup** by killing the process

The app receives the same events as a real mouse click — no XCUITest sandbox.

## Available Helpers

All helpers are bash functions in `Scripts/test-ui.sh`.

### Core helpers

| Helper | Returns | Purpose |
|--------|---------|---------|
| `launch_app [args...]` | — | Start app with launch arguments, waits 3s |
| `kill_app` | — | Terminate app process |
| `click_status_item` | stdout | Click the menu bar status item |
| `window_count` | integer | Number of open windows |
| `window_exists "title"` | "true"/"false" | Check window by title |
| `wait_for_windows N [timeout]` | exit code | Wait for ≥N windows |
| `wait_for_window "title" [timeout]` | exit code | Wait for window to appear |
| `wait_for_window_gone "title" [timeout]` | exit code | Wait for window to close |
| `app_query 'script'` | stdout | Run AppleScript inside `tell System Events ... tell targetApp` |
| `run_as 'full script'` | stdout | Run raw AppleScript |

### Extended helpers

| Helper | Returns | Purpose |
|--------|---------|---------|
| `log_step "description"` | — | Print step marker within a test for debugging |
| `click_group_button N "window"` | exit code | Click button N in group 1 of a named window |
| `click_last_group_button "window"` | exit code | Click last button in group 1 |
| `get_group_button_count "window"` | integer | Count buttons in group 1 |
| `get_group_static_text_count "window"` | integer | Count static texts in group 1 |
| `get_group_static_text N "window"` | string | Get value of static text N in group 1 |
| `window_has_text "text" "window"` | exit code | Check if window contains text |
| `app_is_running` | exit code | Check if the app process is alive |
| `wait_for_app_exit [timeout]` | exit code | Wait for app process to exit |
| `dump_window_contents "window"` | stdout | Dump entire contents (debugging) |

## Writing a Test

### 1. Define a function

```bash
test_my_feature_does_something() {
    launch_app --uitesting -hasCompletedOnboarding 1
    click_status_item >/dev/null
    sleep 1
    wait_for_windows 1 5
}
```

### 2. Register it

Add to the `# main` section at the bottom of `test-ui.sh`:

```bash
run_test "test_my_feature_does_something" test_my_feature_does_something
```

### 3. Return value = pass/fail

Return `0` (or let the function end) for pass. Return non-zero or use a failing `[ condition ]` for fail. `kill_app` is called automatically after each test.

## Common Patterns

### Click a button inside a window

SwiftUI buttons live inside `group 1` of the window, not as direct window children. Title bar buttons (close/minimize/zoom) are direct children.

```bash
# Click the first SwiftUI button in the content area
app_query 'click button 1 of group 1 of window "My Window" of targetApp'

# Click the title bar close button
app_query 'click button 1 of window "My Window" of targetApp'
```

### Count buttons to identify screens

SwiftUI buttons have no accessible name in System Events. Use button count + position:

```bash
count=$(app_query 'return count of buttons of group 1 of window "My Window" of targetApp')
# Screen with 1 button = Welcome, 3 buttons = Calendar connect, 2 buttons = All Set
```

### Check static text

```bash
app_query 'return value of static text 1 of group 1 of window "My Window" of targetApp'
```

### Wait for a condition

```bash
local deadline=$((SECONDS + 10))
while [ "$SECONDS" -lt "$deadline" ]; do
    local result
    result=$(app_query 'return exists window "Expected" of targetApp' 2>/dev/null)
    [ "$result" = "true" ] && return 0
    sleep 0.3
done
return 1
```

## Launch Arguments

| Argument | Effect |
|----------|--------|
| `--uitesting` | Enables UI testing mode (skips AX permission prompts) |
| `--ui-testing-regular-activation` | Forces `.regular` activation policy (app gets Dock icon, windows are frontmost) |
| `-hasCompletedOnboarding 1` | Skip onboarding |
| `-hasCompletedOnboarding 0` | Show onboarding |
| `--inject-test-events` | Populates CalendarService with synthetic events (no real calendar needed) |
| `--show-test-meeting-details` | Opens meeting details popup on launch (requires `--inject-test-events`) |

## Discovering Element Hierarchy

To inspect what's in a window:

```bash
osascript -e '
tell application "System Events"
    set targetApp to first process whose bundle identifier is "com.unmissable.app"
    return entire contents of window 1 of targetApp
end tell
' | tr ',' '\n'
```

## Known Limitations

- Requires **System Events accessibility permission** on the machine
- Requires a **GUI session**
- No Xcode Test Navigator integration — results are script pass/fail
- Button identification is **positional** (no accessible names from SwiftUI)
- SwiftUI `.onTapGesture` elements cannot be clicked via osascript (same root cause as XCUITest — see ADR-002). Use `Button` for elements that need UI test interaction.
- SwiftUI `Text()` inside deeply nested views may not appear as `static text` in System Events. Verify presence by checking group structure (group count, button count) rather than text search.
- MenuBarExtra popover toggles on/off with each status item click. After closing a window that was opened from the popover, the lingering popover must be toggled off before toggling it back on.
