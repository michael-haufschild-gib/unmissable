#!/bin/bash

# XCUITest UI Test Runner
#
# Runs the UI test bundle via xcodebuild.
#
# Usage:
#   ./Scripts/test-ui.sh                    # run all UI tests
#   ./Scripts/test-ui.sh --discovery-only   # run discovery spike only

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

XCODEPROJ="Unmissable.xcodeproj"
SCHEME="UnmissableUITests"
RESULT_BUNDLE="test-reports/ui-tests.xcresult"
DISCOVERY_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --discovery-only)
            DISCOVERY_ONLY=true
            ;;
    esac
done

if [ ! -d "$XCODEPROJ" ]; then
    echo "ERROR: $XCODEPROJ not found."
    echo "Run: xcodegen generate"
    exit 1
fi

rm -rf "$RESULT_BUNDLE"
mkdir -p "$(dirname "$RESULT_BUNDLE")"

echo "=== Running UI Tests ==="

TEST_FILTER=""
if [ "$DISCOVERY_ONLY" = true ]; then
    TEST_FILTER="-only-testing:UnmissableUITests/MenuBarDiscoveryTests"
    echo "Running discovery spike only..."
fi

EXIT_CODE=0
xcodebuild test \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -destination "platform=macOS" \
    -resultBundlePath "$RESULT_BUNDLE" \
    $TEST_FILTER \
    2>&1 || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=== UI Tests PASSED ==="
else
    echo ""
    echo "=== UI Tests FAILED (exit code $EXIT_CODE) ==="
fi

exit $EXIT_CODE
