#!/bin/bash

set -euo pipefail

# Format code with SwiftFormat

echo "✨  Formatting code with SwiftFormat..."
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "❌  SwiftFormat not installed. Run: brew install swiftformat"
    exit 1
fi

swiftformat "$PROJECT_DIR/Sources" "$PROJECT_DIR/Tests" --config "$PROJECT_DIR/.swiftformat"
echo "✅  Code formatting completed!"
