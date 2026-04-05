#!/bin/bash

# Build and test script for Unmissable

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

XCODEPROJ="Unmissable.xcodeproj"
SCHEME="Unmissable"
DESTINATION="platform=macOS,arch=arm64"

echo "Building Unmissable..."
xcodebuild build \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -quiet

echo ""
echo "Running SwiftLint..."
"$PROJECT_DIR/Scripts/enforce-lint.sh"

echo ""
echo "Checking SwiftFormat..."
if ! command -v swiftformat >/dev/null 2>&1; then
    echo "SwiftFormat not installed. Run: brew install swiftformat"
    exit 1
fi
swiftformat Sources Tests --lint

echo ""
echo "Running tests..."
xcodebuild test \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -parallel-testing-worker-count 4 \
    -quiet

echo ""
echo "All checks passed!"
