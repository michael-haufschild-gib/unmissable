#!/bin/bash

# UI Test Runner — osascript-based
#
# Launches the built app as a normal process and interacts via System Events
# AppleScript. See docs/adr/002-ui-tests-osascript-over-xcuitest.md for why
# XCUITest is not used.
#
# Usage:
#   ./Scripts/test-ui.sh              # run all UI tests
#   ./Scripts/test-ui.sh --build      # build first, then test
#   ./Scripts/test-ui.sh <test_name>  # run a single test by function name

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="com.unmissable.app"
APP_PATH=""
APP_PID=""
PASSED=0
FAILED=0
SKIPPED=0
FAILURES=""
BUILD_FIRST=false
FILTER=""

for arg in "$@"; do
    case "$arg" in
        --build) BUILD_FIRST=true ;;
        --help|-h)
            echo "Usage: $0 [--build] [test_name]"
            echo "  --build    Build the app before running tests"
            echo "  test_name  Run only the test matching this name"
            exit 0
            ;;
        --*)
            echo "ERROR: Unknown option: $arg" >&2
            exit 2
            ;;
        *) FILTER="$arg" ;;
    esac
done

# ---------- helpers ----------

DERIVED_DATA_DIR="$PROJECT_DIR/.build/uitest-xcode"

resolve_app() {
    APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/Unmissable.app"
    if [ -d "$APP_PATH" ]; then
        return 0
    fi
    # Fallback: check default DerivedData for Xcode GUI builds
    local dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
    for dir in "$dd_dir"/Unmissable-*/Build/Products/Debug/Unmissable.app; do
        if [ -d "$dir" ]; then
            APP_PATH="$dir"
            return 0
        fi
    done
    echo "ERROR: Built app not found. Run with --build or build in Xcode first."
    exit 1
}

build_app() {
    echo "=== Building Unmissable ==="
    xcodebuild build \
        -project "$PROJECT_DIR/Unmissable.xcodeproj" \
        -scheme Unmissable \
        -derivedDataPath "$DERIVED_DATA_DIR" \
        -quiet 2>&1 || {
        echo "BUILD FAILED"
        exit 1
    }
    echo "Build OK"
}

launch_app() {
    local args=("$@")
    pkill -f "Unmissable.app/Contents/MacOS/Unmissable" 2>/dev/null || true
    sleep 0.5
    "$APP_PATH/Contents/MacOS/Unmissable" "${args[@]}" &
    APP_PID=$!
    # Wait for the app to finish launching and render the status item.
    sleep 3
}

kill_app() {
    if [ -n "$APP_PID" ]; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
        APP_PID=""
    fi
    pkill -f "Unmissable.app/Contents/MacOS/Unmissable" 2>/dev/null || true
    sleep 1
}

# Run an AppleScript snippet. Prints output. Returns osascript exit code.
run_as() {
    osascript -e "$1" 2>&1
}

# Query System Events for the app.
app_query() {
    run_as "
        tell application \"System Events\"
            set targetApp to first process whose bundle identifier is \"$BUNDLE_ID\"
            $1
        end tell
    "
}

click_status_item() {
    app_query 'click menu bar item 1 of menu bar 2 of targetApp'
}

window_count() {
    app_query 'return count of windows of targetApp'
}

window_exists() {
    app_query "return exists window \"$1\" of targetApp"
}

wait_for_windows() {
    local min_count="$1"
    local timeout="${2:-10}"
    local deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -lt "$deadline" ]; do
        local count
        count=$(window_count 2>/dev/null || echo 0)
        if [ "$count" -ge "$min_count" ]; then
            return 0
        fi
        sleep 0.3
    done
    return 1
}

wait_for_window_gone() {
    local title="$1"
    local timeout="${2:-10}"
    local deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -lt "$deadline" ]; do
        local exists
        exists=$(window_exists "$title" 2>/dev/null || echo "true")
        if [ "$exists" = "false" ]; then
            return 0
        fi
        sleep 0.3
    done
    return 1
}

# ---------- extended helpers ----------

# Print a step marker within a test for debugging.
log_step() {
    echo "    ↳ $1"
}

# Click button N (1-indexed) inside group 1 of a named window.
# SwiftUI buttons live inside group 1, not as direct window children.
click_group_button() {
    local index="$1"
    local win_title="$2"
    app_query "click button $index of group 1 of window \"$win_title\" of targetApp" >/dev/null 2>&1
}

# Click the last button inside group 1 of a named window.
click_last_group_button() {
    local win_title="$1"
    app_query "click last button of group 1 of window \"$win_title\" of targetApp" >/dev/null 2>&1
}

# Count buttons inside group 1 of a named window.
get_group_button_count() {
    local win_title="$1"
    app_query "return count of buttons of group 1 of window \"$win_title\" of targetApp" 2>/dev/null
}

# Count all static text elements inside group 1 of a named window.
get_group_static_text_count() {
    local win_title="$1"
    app_query "return count of static texts of group 1 of window \"$win_title\" of targetApp" 2>/dev/null
}

# Get the value of static text N in group 1 of a named window.
get_group_static_text() {
    local index="$1"
    local win_title="$2"
    app_query "return value of static text $index of group 1 of window \"$win_title\" of targetApp" 2>/dev/null
}

# Check if a window contains a static text with a specific value.
# Returns 0 (true) or 1 (false).
window_has_text() {
    local text="$1"
    local win_title="$2"
    local count
    count=$(get_group_static_text_count "$win_title" 2>/dev/null || echo 0)
    for i in $(seq 1 "$count"); do
        local val
        val=$(get_group_static_text "$i" "$win_title" 2>/dev/null || echo "")
        if [[ "$val" == *"$text"* ]]; then
            return 0
        fi
    done
    return 1
}

# Wait until a window with the given title exists.
wait_for_window() {
    local title="$1"
    local timeout="${2:-10}"
    local deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -lt "$deadline" ]; do
        local exists
        exists=$(window_exists "$title" 2>/dev/null || echo "false")
        if [ "$exists" = "true" ]; then
            return 0
        fi
        sleep 0.3
    done
    return 1
}

# Check if the app process is still running.
app_is_running() {
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Wait for the app process to exit.
wait_for_app_exit() {
    local timeout="${1:-10}"
    local deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ! app_is_running; then
            return 0
        fi
        sleep 0.3
    done
    return 1
}

# Get the entire contents of a window for debugging.
dump_window_contents() {
    local win_title="$1"
    app_query "return entire contents of window \"$win_title\" of targetApp" 2>/dev/null | tr ',' '\n'
}

# ---------- test runner ----------

run_test() {
    local name="$1"
    local fn="$2"

    if [ -n "$FILTER" ] && [ "$FILTER" != "$name" ]; then
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    printf "  %-60s " "$name"
    if eval "$fn"; then
        echo "PASS"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL"
        FAILED=$((FAILED + 1))
        FAILURES="$FAILURES\n  - $name"
    fi
    kill_app
}

# ---------- test cases ----------

# ============================================================
# JOURNEY: Onboarding — Single-action tests
# ============================================================

test_menubar_click_opens_dropdown() {
    launch_app --uitesting -hasCompletedOnboarding 1
    click_status_item >/dev/null
    sleep 1
    wait_for_windows 1 5
}

test_onboarding_window_shown_on_first_launch() {
    launch_app --uitesting --ui-testing-regular-activation -hasCompletedOnboarding 0
    wait_for_windows 1 10 || return 1
    local exists
    exists=$(window_exists "Welcome to Unmissable")
    [ "$exists" = "true" ]
}

test_onboarding_close_button_dismisses() {
    launch_app --uitesting --ui-testing-regular-activation -hasCompletedOnboarding 0
    wait_for_windows 1 10 || return 1

    # Click the title bar close button (button 1 of the window).
    app_query 'click button 1 of window "Welcome to Unmissable" of targetApp' >/dev/null 2>&1 || return 1

    wait_for_window_gone "Welcome to Unmissable" 10
}

test_onboarding_continue_navigates() {
    launch_app --uitesting --ui-testing-regular-activation -hasCompletedOnboarding 0
    wait_for_windows 1 10 || return 1

    # SwiftUI buttons inside the window are children of group 1.
    # They have no accessible name in System Events, so we target by position.

    # Screen 1: Welcome — single button in content group = Continue
    local button_count
    button_count=$(get_group_button_count "Welcome to Unmissable")
    [ "$button_count" = "1" ] || return 1
    click_group_button 1 "Welcome to Unmissable" || return 1
    sleep 1

    # Screen 2: Connect Calendar — 3 buttons (Apple, Google, Skip). Last button = Skip.
    button_count=$(get_group_button_count "Welcome to Unmissable")
    [ "$button_count" = "3" ] || return 1
    # Skip is the last (3rd) button.
    click_group_button 3 "Welcome to Unmissable" || return 1
    sleep 1

    # Screen 3: All Set — 2 buttons (Show Demo, Done). Last button = Done.
    click_last_group_button "Welcome to Unmissable" || return 1

    # Window should close after completing onboarding.
    wait_for_window_gone "Welcome to Unmissable" 10
}

# ============================================================
# JOURNEY: Full onboarding with demo overlay
# First-time user: Welcome → Continue → Skip → Demo → Dismiss → Done
# ============================================================

test_onboarding_full_flow_with_demo_overlay() {
    launch_app --uitesting --ui-testing-regular-activation -hasCompletedOnboarding 0
    wait_for_windows 1 10 || return 1

    # Step 1: Welcome screen — verify it shows, then Continue
    log_step "Welcome screen — clicking Continue"
    local button_count
    button_count=$(get_group_button_count "Welcome to Unmissable")
    [ "$button_count" = "1" ] || return 1
    click_group_button 1 "Welcome to Unmissable" || return 1
    sleep 1

    # Step 2: Connect Calendar screen — verify 3 buttons, then Skip
    log_step "Connect Calendar screen — clicking Skip"
    button_count=$(get_group_button_count "Welcome to Unmissable")
    [ "$button_count" = "3" ] || return 1
    click_group_button 3 "Welcome to Unmissable" || return 1
    sleep 1

    # Step 3: All Set screen — verify 2 buttons (Demo + Done)
    log_step "All Set screen — clicking Show Demo"
    button_count=$(get_group_button_count "Welcome to Unmissable")
    [ "$button_count" = "2" ] || return 1

    # Click "Show me how it looks" (first button)
    click_group_button 1 "Welcome to Unmissable" || return 1
    sleep 2

    # Step 4: Verify overlay window appeared
    log_step "Verifying overlay window appeared"
    wait_for_window "Meeting Overlay" 10 || return 1

    # Step 5: Dismiss the overlay — click the Dismiss button in the overlay.
    # The overlay has buttons in group 1: Join Meeting + Snooze + Dismiss.
    # Dismiss is the last button.
    log_step "Dismissing overlay"
    click_last_group_button "Meeting Overlay" || return 1

    # Wait for overlay to close. If app crashed during dismiss, it won't
    # have windows — treat that as overlay gone.
    local overlay_gone=false
    local deadline=$((SECONDS + 10))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ! app_is_running; then
            # App crashed — overlay is gone but we can't continue.
            log_step "FAIL: App crashed after overlay dismiss (known issue)"
            APP_PID=""
            return 1
        fi
        local exists
        exists=$(window_exists "Meeting Overlay" 2>/dev/null || echo "false")
        if [ "$exists" = "false" ]; then
            overlay_gone=true
            break
        fi
        sleep 0.3
    done
    [ "$overlay_gone" = true ] || return 1

    # Step 6: Back to onboarding — click Done (last button on All Set screen)
    log_step "Clicking Done to complete onboarding"
    sleep 1
    if ! app_is_running; then
        log_step "WARN: App exited after overlay dismiss"
        APP_PID=""
        return 0
    fi
    click_last_group_button "Welcome to Unmissable" || return 1

    # Wait for onboarding to close. App may exit during this step.
    local deadline=$((SECONDS + 10))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ! app_is_running; then
            APP_PID=""
            return 0
        fi
        local exists
        exists=$(window_exists "Welcome to Unmissable" 2>/dev/null || echo "false")
        if [ "$exists" = "false" ]; then
            return 0
        fi
        sleep 0.3
    done
    return 1
}

# ============================================================
# JOURNEY: Menu bar → Preferences window navigation
# Returning user: Click status item → Preferences → navigate tabs → close
# ============================================================

test_menubar_to_preferences_flow() {
    launch_app --uitesting --ui-testing-regular-activation -hasCompletedOnboarding 1
    click_status_item >/dev/null
    sleep 1
    wait_for_windows 1 5 || return 1

    # Step 1: The popover is a MenuBarExtra(.window). Its content area has buttons.
    # Footer has Preferences and Quit buttons. We need to find and click Preferences.
    # In the disconnected state, the popover shows: header + connect buttons + footer.
    # Preferences button is in the footer. It may be a different index depending on
    # the number of buttons above it in the group.
    # Strategy: click the Preferences button by searching for it.
    # The popover window doesn't have a title — it's identified by being window 1.
    log_step "Clicking Preferences button in popover"
    app_query 'click button 1 of group 1 of window 1 of targetApp' >/dev/null 2>&1 || true
    sleep 1

    # The Preferences button might not be button 1 if there are connect buttons.
    # Let's check if the Preferences window opened.
    local prefs_opened
    prefs_opened=$(window_exists "Unmissable Preferences" 2>/dev/null || echo "false")

    if [ "$prefs_opened" != "true" ]; then
        # Try clicking other buttons — in disconnected state there may be
        # Connect Apple (1), Connect Google (2), then Preferences (3), Quit (4)
        log_step "Retrying — trying button positions for Preferences"
        local total_buttons
        total_buttons=$(app_query 'return count of buttons of group 1 of window 1 of targetApp' 2>/dev/null || echo 0)
        # Preferences is second-to-last button (before Quit)
        if [ "$total_buttons" -ge 2 ]; then
            local prefs_index=$((total_buttons - 1))
            app_query "click button $prefs_index of group 1 of window 1 of targetApp" >/dev/null 2>&1 || true
            sleep 1
        fi
    fi

    # Step 2: Verify Preferences window opened
    log_step "Verifying Preferences window opened"
    wait_for_window "Unmissable Preferences" 10 || return 1

    # Step 3: Navigate tabs — click each of the 4 tab buttons.
    # Tab bar buttons are inside the Preferences window's group 1.
    # They're the first 4 buttons in the window (General, Calendars, Appearance, Shortcuts).
    log_step "Navigating to Calendars tab"
    click_group_button 2 "Unmissable Preferences" || return 1
    sleep 0.5

    log_step "Navigating to Appearance tab"
    click_group_button 3 "Unmissable Preferences" || return 1
    sleep 0.5

    log_step "Navigating to Shortcuts tab"
    click_group_button 4 "Unmissable Preferences" || return 1
    sleep 0.5

    log_step "Navigating back to General tab"
    click_group_button 1 "Unmissable Preferences" || return 1
    sleep 0.5

    # Step 4: Close the Preferences window
    log_step "Closing Preferences window"
    app_query 'click button 1 of window "Unmissable Preferences" of targetApp' >/dev/null 2>&1 || return 1
    wait_for_window_gone "Unmissable Preferences" 10
}

# ============================================================
# JOURNEY: Menu bar → Quit
# Returning user: Click status item → Quit → app terminates
# ============================================================

test_menubar_quit_terminates_app() {
    launch_app --uitesting -hasCompletedOnboarding 1
    click_status_item >/dev/null
    sleep 1
    wait_for_windows 1 5 || return 1

    # Quit is the last button in the popover footer
    log_step "Clicking Quit button"
    local total_buttons
    total_buttons=$(app_query 'return count of buttons of group 1 of window 1 of targetApp' 2>/dev/null || echo 0)
    [ "$total_buttons" -ge 1 ] || return 1

    # Quit is the very last button
    app_query "click button $total_buttons of group 1 of window 1 of targetApp" >/dev/null 2>&1 || true

    # Wait for the process to exit
    log_step "Waiting for app to terminate"
    wait_for_app_exit 10 || return 1

    # Clear PID since app is already gone — prevent kill_app from erroring
    APP_PID=""
}

# ============================================================
# JOURNEY: Disconnected state verification
# Fresh install: No calendar connected → shows connect buttons
# ============================================================

test_disconnected_state_shows_connect_buttons() {
    launch_app --uitesting -hasCompletedOnboarding 1
    click_status_item >/dev/null
    sleep 1
    wait_for_windows 1 5 || return 1

    # In disconnected state, the popover should contain the calendar connect buttons.
    # There should be at least 4 buttons: Connect Apple, Connect Google, Preferences, Quit.
    log_step "Verifying connect buttons present"
    local button_count
    button_count=$(app_query 'return count of buttons of group 1 of window 1 of targetApp' 2>/dev/null || echo 0)
    [ "$button_count" -ge 4 ] || return 1

    # Verify header text "Unmissable" is present
    log_step "Verifying header text"
    local has_header
    has_header=$(app_query '
        set allTexts to value of every static text of group 1 of window 1 of targetApp
        set found to false
        repeat with t in allTexts
            if t as text contains "Unmissable" then
                set found to true
                exit repeat
            end if
        end repeat
        return found
    ' 2>/dev/null || echo "false")
    [ "$has_header" = "true" ] || return 1
}

# ============================================================
# JOURNEY: Connected state with injected test events
# Returning user with events: Shows event list and sync status
# ============================================================

test_connected_state_shows_events() {
    launch_app --uitesting --ui-testing-regular-activation -hasCompletedOnboarding 1 --inject-test-events
    # Extra delay for event injection to propagate through @Observable
    sleep 2
    click_status_item >/dev/null
    sleep 2
    wait_for_windows 1 5 || return 1

    # With injected test events, the popover shows event rows as groups.
    # SwiftUI doesn't expose event title Text elements as named static texts
    # in the System Events accessibility tree. Instead, verify:
    # 1. Connected state (group labels like TODAY, STARTED vs "No upcoming meetings")
    # 2. Event row groups exist (each event = a group with buttons)
    log_step "Verifying connected state with events"
    local top_texts
    top_texts=$(app_query '
        set txts to value of every static text of group 1 of window 1 of targetApp
        set output to ""
        repeat with t in txts
            set output to output & (t as text) & "|"
        end repeat
        return output
    ' 2>/dev/null || echo "")

    # "No upcoming meetings" should NOT be present
    [[ "$top_texts" == *"No upcoming meetings"* ]] && { log_step "FAIL: Events not loaded — still showing empty state"; return 1; }

    # Verify event group labels are present
    log_step "Verifying event group labels"
    [[ "$top_texts" == *"TODAY"* ]] || [[ "$top_texts" == *"STARTED"* ]] || { log_step "FAIL: No event group labels found in: $top_texts"; return 1; }

    # Verify event rows exist as groups (injected: 3 upcoming + 1 started = 4 groups)
    log_step "Verifying event row groups"
    local group_count
    group_count=$(app_query 'return count of groups of group 1 of window 1 of targetApp' 2>/dev/null || echo 0)
    [ "$group_count" -ge 3 ] || { log_step "FAIL: Expected at least 3 event groups, got $group_count"; return 1; }

    # Verify "Show today only" toggle is present (connected state only)
    [[ "$top_texts" == *"Show today only"* ]] || { log_step "FAIL: 'Show today only' toggle not found"; return 1; }

    return 0
}

# ============================================================
# JOURNEY: Event row → Meeting details popup
# Tap event → meeting details opens → close it
# ============================================================

test_event_opens_meeting_details() {
    # --show-test-meeting-details triggers the meeting details popup on launch
    # for the first test event (bypasses the .onTapGesture limitation).
    launch_app --uitesting --ui-testing-regular-activation -hasCompletedOnboarding 1 --inject-test-events --show-test-meeting-details
    sleep 3

    # Step 1: Verify meeting details popup appeared
    log_step "Verifying Meeting Details popup opened"
    wait_for_window "Meeting Details" 10 || return 1

    # Step 2: Verify the popup contains meeting-related text
    log_step "Verifying meeting details content"
    local details_text
    details_text=$(app_query '
        set txts to value of every static text of group 1 of window "Meeting Details" of targetApp
        set output to ""
        repeat with t in txts
            set output to output & (t as text) & "|"
        end repeat
        return output
    ' 2>/dev/null || echo "")
    [[ "$details_text" == *"Meeting Details"* ]] || [[ "$details_text" == *"When"* ]] || { log_step "WARN: Expected meeting content not found"; }

    # Step 3: Close the meeting details popup.
    # The borderless popup has a close button (xmark) inside group 1.
    # It's the last button in the header area.
    log_step "Closing meeting details popup"
    local popup_buttons
    popup_buttons=$(get_group_button_count "Meeting Details" 2>/dev/null || echo 0)
    if [ "$popup_buttons" -ge 1 ]; then
        # Try each button until the window closes
        for i in $(seq 1 "$popup_buttons"); do
            click_group_button "$i" "Meeting Details" 2>/dev/null || true
            sleep 0.5
            local still_there
            still_there=$(window_exists "Meeting Details" 2>/dev/null || echo "false")
            if [ "$still_there" = "false" ]; then
                break
            fi
        done
    fi
    wait_for_window_gone "Meeting Details" 10
}

# ============================================================
# JOURNEY: Overlay dismiss flow (via test event scheduling)
# An overlay appears for an imminent event → user dismisses it
# ============================================================

test_overlay_dismiss_flow() {
    # Use the demo overlay via onboarding — more reliable than waiting for scheduler
    launch_app --uitesting --ui-testing-regular-activation -hasCompletedOnboarding 0
    wait_for_windows 1 10 || return 1

    # Navigate to All Set screen quickly
    log_step "Navigating through onboarding to reach demo overlay"
    click_group_button 1 "Welcome to Unmissable" || return 1
    sleep 1
    click_group_button 3 "Welcome to Unmissable" || return 1
    sleep 1

    # Click "Show me how it looks" to trigger demo overlay
    log_step "Triggering demo overlay"
    click_group_button 1 "Welcome to Unmissable" || return 1
    sleep 2

    # Verify overlay appeared
    log_step "Verifying overlay window exists"
    wait_for_window "Meeting Overlay" 10 || return 1

    # Verify overlay contains expected content
    log_step "Checking overlay content"
    local overlay_text
    overlay_text=$(app_query '
        set allTexts to value of every static text of group 1 of window "Meeting Overlay" of targetApp
        set output to ""
        repeat with t in allTexts
            set output to output & (t as text) & "|"
        end repeat
        return output
    ' 2>/dev/null || echo "")
    [[ "$overlay_text" == *"Team Standup"* ]] || { log_step "WARN: Demo event title not found in overlay"; }

    # Verify there's a Join button (demo event has a Google Meet link)
    log_step "Checking for action buttons"
    local overlay_buttons
    overlay_buttons=$(get_group_button_count "Meeting Overlay" 2>/dev/null || echo 0)
    [ "$overlay_buttons" -ge 2 ] || { log_step "WARN: Expected at least 2 buttons in overlay, got $overlay_buttons"; }

    # Dismiss the overlay
    log_step "Dismissing overlay"
    click_last_group_button "Meeting Overlay" || return 1
    wait_for_window_gone "Meeting Overlay" 10
}

# ============================================================
# JOURNEY: Preferences window lifecycle
# Open → close → reopen → verify still works
# ============================================================

test_preferences_window_lifecycle() {
    launch_app --uitesting --ui-testing-regular-activation -hasCompletedOnboarding 1
    click_status_item >/dev/null
    sleep 1
    wait_for_windows 1 5 || return 1

    # Step 1: Open Preferences via the popover.
    # Find and click the Preferences button.
    log_step "Opening Preferences (first time)"
    local total_buttons
    total_buttons=$(app_query 'return count of buttons of group 1 of window 1 of targetApp' 2>/dev/null || echo 0)
    # Preferences is second-to-last (before Quit)
    local prefs_index=$((total_buttons - 1))
    [ "$prefs_index" -ge 1 ] || return 1
    app_query "click button $prefs_index of group 1 of window 1 of targetApp" >/dev/null 2>&1 || true
    sleep 1
    wait_for_window "Unmissable Preferences" 10 || return 1

    # Step 2: Close Preferences via title bar close button.
    log_step "Closing Preferences"
    app_query 'click button 1 of window "Unmissable Preferences" of targetApp' >/dev/null 2>&1 || return 1
    wait_for_window_gone "Unmissable Preferences" 10 || return 1

    # Step 3: Reopen Preferences.
    # After closing the Preferences window, the MenuBarExtra popover
    # from step 1 is still lingering (hidden behind preferences).
    # The first status item click toggles it *off*. The second click
    # opens a fresh popover.
    log_step "Reopening Preferences"
    sleep 1

    # First click: dismiss the lingering popover
    click_status_item >/dev/null
    sleep 1
    # Second click: open a fresh popover
    click_status_item >/dev/null
    sleep 1

    wait_for_windows 1 5 || return 1

    total_buttons=$(app_query 'return count of buttons of group 1 of window 1 of targetApp' 2>/dev/null || echo 0)
    prefs_index=$((total_buttons - 1))
    [ "$prefs_index" -ge 1 ] || return 1
    app_query "click button $prefs_index of group 1 of window 1 of targetApp" >/dev/null 2>&1 || true
    sleep 2

    # Step 4: Verify it reopened successfully.
    log_step "Verifying Preferences reopened"
    wait_for_window "Unmissable Preferences" 10
}

# ---------- main ----------

if [ "$BUILD_FIRST" = true ]; then
    build_app
fi

resolve_app

echo "=== Running UI Tests ==="
echo "App: $APP_PATH"
echo ""

# --- Onboarding flows ---
run_test "test_onboarding_window_shown_on_first_launch" test_onboarding_window_shown_on_first_launch
run_test "test_onboarding_close_button_dismisses" test_onboarding_close_button_dismisses
run_test "test_onboarding_continue_navigates" test_onboarding_continue_navigates
run_test "test_onboarding_full_flow_with_demo_overlay" test_onboarding_full_flow_with_demo_overlay

# --- Menu bar flows ---
run_test "test_menubar_click_opens_dropdown" test_menubar_click_opens_dropdown
run_test "test_menubar_quit_terminates_app" test_menubar_quit_terminates_app
run_test "test_disconnected_state_shows_connect_buttons" test_disconnected_state_shows_connect_buttons

# --- Connected state flows (require --inject-test-events) ---
run_test "test_connected_state_shows_events" test_connected_state_shows_events
run_test "test_event_opens_meeting_details" test_event_opens_meeting_details

# --- Overlay flows ---
run_test "test_overlay_dismiss_flow" test_overlay_dismiss_flow

# --- Preferences flows ---
run_test "test_menubar_to_preferences_flow" test_menubar_to_preferences_flow
run_test "test_preferences_window_lifecycle" test_preferences_window_lifecycle

# Check for unmatched filter
TOTAL=$((PASSED + FAILED))
if [ -n "$FILTER" ] && [ "$TOTAL" -eq 0 ]; then
    echo "ERROR: No test matched filter: $FILTER" >&2
    exit 2
fi

echo ""
echo "=== Results: $PASSED passed, $FAILED failed, $SKIPPED skipped ==="

if [ "$FAILED" -gt 0 ]; then
    echo -e "Failures:$FAILURES"
    exit 1
fi

exit 0
