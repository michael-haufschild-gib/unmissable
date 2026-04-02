#!/bin/bash

# Full SwiftLint enforcement gate.
# Runs ALL rules (custom + standard) with --strict so warnings also fail the gate.
# Called by build.sh and can be used as a pre-commit hook.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${LINT_GATE_PLUGIN_OUTPUT_DIR:-${TMPDIR:-/tmp}/unmissable-lint-gate-output}"
CACHE_DIR="${LINT_GATE_CACHE_DIR:-${TMPDIR:-/tmp}/unmissable-swiftlint-cache}"
HOME_DIR="${LINT_GATE_HOME_DIR:-${TMPDIR:-/tmp}/unmissable-lint-gate-home}"

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR" "$HOME_DIR"
export HOME="$HOME_DIR"
cd "$PROJECT_DIR"

SWIFTLINT_BIN=""
if command -v swiftlint >/dev/null 2>&1; then
    SWIFTLINT_BIN="$(command -v swiftlint)"
elif [ -x /opt/homebrew/bin/swiftlint ]; then
    SWIFTLINT_BIN="/opt/homebrew/bin/swiftlint"
elif [ -x /usr/local/bin/swiftlint ]; then
    SWIFTLINT_BIN="/usr/local/bin/swiftlint"
elif xcrun --find swiftlint >/dev/null 2>&1; then
    SWIFTLINT_BIN="$(xcrun --find swiftlint)"
fi

if [ -z "$SWIFTLINT_BIN" ]; then
    echo "SwiftLint is required. Install with: brew install swiftlint"
    exit 1
fi

# Run full SwiftLint with --strict: warnings are treated as errors.
# This enforces ALL rules in .swiftlint.yml, not just a subset.
"$SWIFTLINT_BIN" lint \
    --strict \
    --config "$PROJECT_DIR/.swiftlint.yml" \
    --cache-path "$CACHE_DIR" \
    "$PROJECT_DIR"

touch "$OUTPUT_DIR/lint-complete"
