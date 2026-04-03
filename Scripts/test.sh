#!/bin/bash

# Unmissable Test Runner
#
# Single entry point for running tests. Addresses:
# - Zombie swift-test process cleanup
# - Separate lint → build → test phases with distinct exit codes
# - Enforced parallel worker limit (no bare swift test)
# - Hard timeout to prevent hangs
# - Machine-readable JSON summary
#
# Usage:
#   ./Scripts/test.sh                              # all tests
#   ./Scripts/test.sh ThemeManagerTests             # filter by class
#   ./Scripts/test.sh UnmissableTests               # filter by target
#   ./Scripts/test.sh --clean                       # wipe .build, then test
#   ./Scripts/test.sh --clean ThemeManagerTests      # wipe .build + filter
#   ./Scripts/test.sh --skip-lint                   # skip lint phase
#   ./Scripts/test.sh --skip-lint ThemeManagerTests  # skip lint + filter

set -euo pipefail

# --- Configuration ---

MAX_WORKERS=4
TIMEOUT_SECONDS=300  # 5 minutes
HEARTBEAT_INTERVAL=30
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

LOG_DIR="$PROJECT_DIR/.build/test-logs"
LOG_FILE="$LOG_DIR/test-output.log"
RESULT_FILE="$PROJECT_DIR/.build/test-result.json"

mkdir -p "$LOG_DIR"

# --- Parse arguments ---

CLEAN=false
SKIP_LINT=false
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --clean)
            CLEAN=true
            shift
            ;;
        --skip-lint)
            SKIP_LINT=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--clean] [--skip-lint] [filter]"
            echo ""
            echo "Options:"
            echo "  --clean       Remove .build directory before building"
            echo "  --skip-lint   Skip the SwiftLint check"
            echo "  filter        Test specifier (target, class, or method)"
            echo ""
            echo "Examples:"
            echo "  $0                                    # all tests"
            echo "  $0 ThemeManagerTests                  # one class"
            echo "  $0 UnmissableTests                    # one target"
            echo "  $0 UnmissableTests/ThemeManagerTests  # target/class"
            echo "  $0 --clean                            # clean build + all tests"
            exit 0
            ;;
        *)
            FILTER="$1"
            shift
            ;;
    esac
done

# --- Helpers ---

write_result() {
    local status="$1"
    local tests="${2:-0}"
    local failures="${3:-0}"
    local duration="${4:-0}"
    local detail="${5:-}"

    cat > "$RESULT_FILE" <<ENDJSON
{
  "status": "$status",
  "tests": $tests,
  "failures": $failures,
  "duration_seconds": $duration,
  "filter": "$FILTER",
  "detail": "$detail",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
ENDJSON
}

die() {
    local status="$1"
    local message="$2"
    echo "$status: $message" >&2
    write_result "$status" 0 0 0 "$message"
    exit 1
}

# --- Step 1: Kill zombie swift-test processes ---

ZOMBIES=$(pgrep -f "swift-test" 2>/dev/null || true)
if [ -n "$ZOMBIES" ]; then
    echo "Killing stale swift-test processes: $ZOMBIES"
    # shellcheck disable=SC2086
    kill $ZOMBIES 2>/dev/null || true
    sleep 1
    # Force-kill any survivors
    REMAINING=$(pgrep -f "swift-test" 2>/dev/null || true)
    if [ -n "$REMAINING" ]; then
        # shellcheck disable=SC2086
        kill -9 $REMAINING 2>/dev/null || true
    fi
fi

# --- Step 2: Clean build directory (if requested) ---

if [ "$CLEAN" = true ]; then
    echo "Cleaning .build directory..."
    rm -rf "$PROJECT_DIR/.build"
    mkdir -p "$LOG_DIR"
fi

# --- Step 3: Lint check ---

if [ "$SKIP_LINT" = false ]; then
    echo "--- LINT ---"
    if ! "$PROJECT_DIR/Scripts/enforce-lint.sh" 2>&1; then
        die "LINT_FAIL" "SwiftLint violations found. Fix lint errors before running tests."
    fi
    echo "Lint: OK"
fi

# --- Step 4: Build (separate from test) ---

echo "--- BUILD ---"
BUILD_START=$(date +%s)
if ! swift build 2>&1 | tee "$LOG_DIR/build-output.log"; then
    die "BUILD_FAIL" "swift build failed. Check $LOG_DIR/build-output.log"
fi
BUILD_END=$(date +%s)
echo "Build: OK ($(( BUILD_END - BUILD_START ))s)"

# --- Step 5: Run tests ---

echo "--- TEST ---"

FILTER_ARG=""
if [ -n "$FILTER" ]; then
    FILTER_ARG="--filter $FILTER"
    echo "Filter: $FILTER"
fi

# Truncate log file
> "$LOG_FILE"

TEST_START=$(date +%s)

# Start heartbeat in background — prints a dot every HEARTBEAT_INTERVAL seconds
# so CLI tools know the process is alive.
(
    while true; do
        sleep "$HEARTBEAT_INTERVAL"
        ELAPSED=$(( $(date +%s) - TEST_START ))
        echo "[heartbeat] tests running... ${ELAPSED}s elapsed"
    done
) &
HEARTBEAT_PID=$!

# Ensure heartbeat is cleaned up on exit
cleanup() {
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Run tests with timeout.
# --skip-build because we already built in step 4.
# 2>&1 merges stderr (where swift test writes progress) into stdout.
TEST_EXIT=0
if command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout"
else
    TIMEOUT_CMD=""
fi

if [ -n "$TIMEOUT_CMD" ]; then
    # shellcheck disable=SC2086
    $TIMEOUT_CMD "$TIMEOUT_SECONDS" \
        swift test --skip-build --parallel --num-workers "$MAX_WORKERS" $FILTER_ARG 2>&1 \
        | tee "$LOG_FILE" || TEST_EXIT=$?
else
    # No timeout command available — run with a background watchdog
    # shellcheck disable=SC2086
    swift test --skip-build --parallel --num-workers "$MAX_WORKERS" $FILTER_ARG 2>&1 \
        | tee "$LOG_FILE" &
    TEST_PID=$!

    # Watchdog: kill after TIMEOUT_SECONDS
    (
        sleep "$TIMEOUT_SECONDS"
        if kill -0 "$TEST_PID" 2>/dev/null; then
            echo "TIMEOUT: Tests exceeded ${TIMEOUT_SECONDS}s limit. Killing."
            kill "$TEST_PID" 2>/dev/null || true
            sleep 2
            kill -9 "$TEST_PID" 2>/dev/null || true
        fi
    ) &
    WATCHDOG_PID=$!

    wait "$TEST_PID" || TEST_EXIT=$?
    kill "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
fi

TEST_END=$(date +%s)
TEST_DURATION=$(( TEST_END - TEST_START ))

# Kill heartbeat now (trap will also try, harmless)
kill "$HEARTBEAT_PID" 2>/dev/null || true

# --- Step 6: Parse results ---

# Check for timeout (exit code 124 from GNU timeout, or our watchdog message)
if [ "$TEST_EXIT" -eq 124 ] 2>/dev/null || grep -q "^TIMEOUT:" "$LOG_FILE" 2>/dev/null; then
    echo ""
    echo "TIMEOUT (tests exceeded ${TIMEOUT_SECONDS}s)"
    write_result "TIMEOUT" 0 0 "$TEST_DURATION" "Hard timeout after ${TIMEOUT_SECONDS}s"
    exit 1
fi

# Parse XCTest summary line: "Executed N tests, with M failures (X unexpected) in Y.ZZZ (A.BBB) seconds"
SUMMARY_LINE=$(grep -E "^Executed [0-9]+ tests?" "$LOG_FILE" | tail -1 || true)

if [ -n "$SUMMARY_LINE" ]; then
    TOTAL_TESTS=$(echo "$SUMMARY_LINE" | sed -E 's/^Executed ([0-9]+) tests?.*/\1/')
    TOTAL_FAILURES=$(echo "$SUMMARY_LINE" | sed -E 's/.*with ([0-9]+) failure.*/\1/')
    # Handle "with 0 failures" vs "with 1 failure"
    if ! echo "$TOTAL_FAILURES" | grep -qE '^[0-9]+$'; then
        TOTAL_FAILURES=0
    fi
else
    TOTAL_TESTS=0
    TOTAL_FAILURES=0
fi

# --- Step 7: Report ---

echo ""
if [ "$TEST_EXIT" -eq 0 ] && [ "$TOTAL_FAILURES" -eq 0 ]; then
    echo "PASS ($TOTAL_TESTS tests, 0 failures, ${TEST_DURATION}s)"
    write_result "PASS" "$TOTAL_TESTS" 0 "$TEST_DURATION"
    exit 0
else
    # Collect failing test names
    FAILING_TESTS=$(grep -E "^\s*(✗|✘|x )" "$LOG_FILE" 2>/dev/null | head -20 || true)
    echo "FAIL ($TOTAL_TESTS tests, $TOTAL_FAILURES failures, ${TEST_DURATION}s)"
    if [ -n "$FAILING_TESTS" ]; then
        echo ""
        echo "Failing tests:"
        echo "$FAILING_TESTS"
    fi
    write_result "FAIL" "$TOTAL_TESTS" "$TOTAL_FAILURES" "$TEST_DURATION" "See $LOG_FILE for details"
    exit 1
fi
