#!/bin/bash

# Build and test script for Unmissable

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🏗️  Building Unmissable..."
swift build

echo ""
echo "🧹  Running SwiftLint..."
"$PROJECT_DIR/Scripts/enforce-lint.sh"

echo ""
echo "✨  Checking SwiftFormat..."
if command -v swiftformat >/dev/null 2>&1; then
    swiftformat Sources Tests --lint
else
    echo "⚠️  SwiftFormat not installed. Run: brew install swiftformat"
fi

echo ""
echo "🧪  Running tests..."

TEST_LOG="$(mktemp -t unmissable-build-tests)"
cleanup() {
    rm -f "$TEST_LOG"
}
trap cleanup EXIT

xcodebuild -scheme Unmissable -destination "platform=macOS" test | tee "$TEST_LOG"

if ! grep -Eq "Executed [1-9][0-9]* test" "$TEST_LOG"; then
    echo "❌ XCTest reported zero executed tests. Failing build to avoid false confidence."
    exit 1
fi

echo ""
echo "✅  All checks passed!"
