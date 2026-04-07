#!/bin/bash

# Unmissable Test Runner
#
# Single entry point for running tests via xcodebuild.
#
# Usage:
#   ./Scripts/test.sh                              # all tests
#   ./Scripts/test.sh UnmissableTests               # filter by target
#   ./Scripts/test.sh E2ETests                      # filter by target
#   ./Scripts/test.sh --clean                       # clean, then test
#   ./Scripts/test.sh --skip-lint                   # skip lint phase
#   ./Scripts/test.sh --skip-lint E2ETests           # skip lint + target filter

set -euo pipefail

# --- Configuration ---

MAX_WORKERS=4
DEFAULT_TIMEOUT=300  # 5 minutes for full suite
E2E_TIMEOUT=120      # 2 minutes for E2E tests
HEARTBEAT_INTERVAL=15
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

XCODEPROJ="Unmissable.xcodeproj"
SCHEME="Unmissable"
DESTINATION="platform=macOS"

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
            echo "  --clean       Clean build artifacts before building"
            echo "  --skip-lint   Skip the SwiftLint check"
            echo "  filter        Test target name (UnmissableTests, E2ETests, IntegrationTests)"
            echo ""
            echo "Examples:"
            echo "  $0                                    # all tests"
            echo "  $0 UnmissableTests                    # one target"
            echo "  $0 E2ETests                           # E2E tests"
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

# --- Step 1: Clean (if requested) ---

if [ "$CLEAN" = true ]; then
    echo "Cleaning build artifacts..."
    xcodebuild clean -project "$XCODEPROJ" -scheme "$SCHEME" -quiet 2>/dev/null || true
fi

# --- Step 2: Lint check ---

if [ "$SKIP_LINT" = false ]; then
    echo "--- LINT ---"
    if ! "$PROJECT_DIR/Scripts/enforce-lint.sh" 2>&1; then
        die "LINT_FAIL" "SwiftLint violations found. Fix lint errors before running tests."
    fi
    echo "Lint: OK"
fi

# --- Step 3: Build for testing ---

echo "--- BUILD ---"
BUILD_START=$(date +%s)
if ! xcodebuild build-for-testing \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -quiet 2>&1 | tee "$LOG_DIR/build-output.log"; then
    die "BUILD_FAIL" "xcodebuild build-for-testing failed. Check $LOG_DIR/build-output.log"
fi
BUILD_END=$(date +%s)
echo "Build: OK ($(( BUILD_END - BUILD_START ))s)"

# --- Step 4: Run tests ---

echo "--- TEST ---"

FILTER_ARG=""
if [ -n "$FILTER" ]; then
    FILTER_ARG="-only-testing:$FILTER"
    echo "Filter: $FILTER"
fi

# Select timeout based on target
if echo "$FILTER" | grep -qi "e2e"; then
    TIMEOUT_SECONDS=$E2E_TIMEOUT
else
    TIMEOUT_SECONDS=$DEFAULT_TIMEOUT
fi
echo "Timeout: ${TIMEOUT_SECONDS}s"

# Truncate log file
> "$LOG_FILE"

TEST_START=$(date +%s)

# Start heartbeat in background
(
    while true; do
        sleep "$HEARTBEAT_INTERVAL"
        ELAPSED=$(( $(date +%s) - TEST_START ))
        echo "[heartbeat] tests running... ${ELAPSED}s elapsed"
    done
) &
HEARTBEAT_PID=$!

cleanup() {
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
}
trap cleanup EXIT

TEST_EXIT=0

# Build the xcodebuild test command as an array to avoid shell injection via FILTER.
XCODEBUILD_CMD=(
    xcodebuild test-without-building
    -project "$XCODEPROJ"
    -scheme "$SCHEME"
    -destination "$DESTINATION"
    -parallel-testing-worker-count "$MAX_WORKERS"
)

if [ -n "$FILTER_ARG" ]; then
    XCODEBUILD_CMD+=("$FILTER_ARG")
fi

# Run in background with watchdog
(
    set -o pipefail
    "${XCODEBUILD_CMD[@]}" 2>&1 | tee "$LOG_FILE"
) &
TEST_PID=$!

# Watchdog
(
    sleep "$TIMEOUT_SECONDS"
    if kill -0 "$TEST_PID" 2>/dev/null; then
        echo "TIMEOUT: Tests exceeded ${TIMEOUT_SECONDS}s limit. Killing."
        kill -- -"$TEST_PID" 2>/dev/null || kill "$TEST_PID" 2>/dev/null || true
        sleep 2
        kill -9 -- -"$TEST_PID" 2>/dev/null || kill -9 "$TEST_PID" 2>/dev/null || true
    fi
) &
WATCHDOG_PID=$!

wait "$TEST_PID" || TEST_EXIT=$?
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true

TEST_END=$(date +%s)
TEST_DURATION=$(( TEST_END - TEST_START ))

kill "$HEARTBEAT_PID" 2>/dev/null || true

# --- Step 5: Parse results ---

if [ -f "$LOG_FILE" ]; then
    sed -i '' $'s/\x1b\\[[0-9;]*[a-zA-Z]//g; s/\r//g' "$LOG_FILE"
fi

# Check for timeout
if [ "$TEST_EXIT" -eq 124 ] 2>/dev/null || grep -q "^TIMEOUT:" "$LOG_FILE" 2>/dev/null; then
    echo ""
    echo "TIMEOUT (tests exceeded ${TIMEOUT_SECONDS}s)"
    write_result "TIMEOUT" 0 0 "$TEST_DURATION" "Hard timeout after ${TIMEOUT_SECONDS}s"
    exit 1
fi

# Parse test results — supports both Swift Testing ("✔ Test foo() passed") and
# XCTest ("Test Case '-[Class method]' passed") output formats.
# Individual Swift Testing tests contain "()" in the method name; summary lines
# ("Test run with N tests ...") do not, so the "\(\)" anchor excludes summaries.
SWIFT_TESTING_TOTAL=$(grep -cE '^[✔✘] Test .*\(\).*(passed|failed)' "$LOG_FILE" 2>/dev/null || true)
XCTEST_TOTAL=$(grep -cE 'Test Case.*(passed|failed)' "$LOG_FILE" 2>/dev/null || true)
TOTAL_TESTS=$(( ${SWIFT_TESTING_TOTAL:-0} + ${XCTEST_TOTAL:-0} ))

SWIFT_TESTING_FAILURES=$(grep -cE '^✘ Test .*\(\).*failed' "$LOG_FILE" 2>/dev/null || true)
XCTEST_FAILURES=$(grep -cE 'Test Case.*failed' "$LOG_FILE" 2>/dev/null || true)
TOTAL_FAILURES=$(( ${SWIFT_TESTING_FAILURES:-0} + ${XCTEST_FAILURES:-0} ))

# --- Step 6: Report ---

echo ""
if [ "$TOTAL_TESTS" -gt 0 ] && [ "$TOTAL_FAILURES" -eq 0 ]; then
    echo "PASS ($TOTAL_TESTS tests, 0 failures, ${TEST_DURATION}s)"
    write_result "PASS" "$TOTAL_TESTS" 0 "$TEST_DURATION"
    exit 0
else
    FAILING_TESTS=$(grep -E '^✘ Test .*\(\).*failed|Test Case.*failed' "$LOG_FILE" 2>/dev/null | head -20 || true)
    echo "FAIL ($TOTAL_TESTS tests, $TOTAL_FAILURES failures, ${TEST_DURATION}s)"
    if [ -n "$FAILING_TESTS" ]; then
        echo ""
        echo "Failing tests:"
        echo "$FAILING_TESTS"
    fi
    write_result "FAIL" "$TOTAL_TESTS" "$TOTAL_FAILURES" "$TEST_DURATION" "See $LOG_FILE for details"
    exit 1
fi
