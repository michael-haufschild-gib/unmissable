#!/bin/bash

# Complete build and install workflow for Unmissable
# This script demonstrates the full process from source to installed app

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE_PATH="${PROJECT_DIR}/Unmissable.app"
APP_EXECUTABLE_PATH="${APP_BUNDLE_PATH}/Contents/MacOS/Unmissable"
cd "$PROJECT_DIR"

echo "🚀  Unmissable Release Workflow"
echo "==============================="
echo ""

# Step 1: Build the release
echo "📦  Step 1: Building release version..."
"${PROJECT_DIR}/Scripts/build-release.sh"
echo ""

# Step 2: Show what was created
echo "🔍  Step 2: Verifying app bundle..."
echo "App bundle location: ${APP_BUNDLE_PATH}"
echo "App bundle size: $(du -sh "${APP_BUNDLE_PATH}" | cut -f1)"
echo "Executable size: $(du -sh "${APP_EXECUTABLE_PATH}" | cut -f1)"
echo ""

# Step 3: Test the app
echo "🧪  Step 3: Testing app launch..."
echo "Opening app for verification (will appear in menu bar)..."
if open "${APP_BUNDLE_PATH}"; then
    sleep 2
    echo "✅  App should now be running in menu bar"
else
    echo "⚠️  Could not open app automatically in this environment. You can launch it manually from Applications after install."
fi
echo ""

# Step 4: Show installation options
echo "📋  Step 4: Installation options..."
echo ""
echo "Option A - Automatic install:"
echo "   ./Scripts/install.sh"
echo ""
echo "Option B - Manual install:"
echo "   1. Drag Unmissable.app to /Applications/"
echo "   2. Right-click and 'Open' (first time only)"
echo "   3. Add to Login Items in System Settings"
echo ""

# Step 5: Configuration check
echo "🔧  Step 5: Configuration verification..."
if [ -d "$HOME/Library/Application Support/Unmissable" ]; then
    echo "✅  Configuration directory exists"
    echo "   Location: ~/Library/Application Support/Unmissable/"
    if [ -f "$HOME/Library/Application Support/Unmissable/unmissable.db" ]; then
        echo "✅  Database file exists ($(du -sh "$HOME/Library/Application Support/Unmissable/unmissable.db" | cut -f1))"
    fi
else
    echo "⚠️  Configuration directory not found (will be created on first run)"
fi
echo ""

echo "🎉  Release workflow complete!"
echo ""
echo "📖  For detailed instructions, see README.md"
echo "🔧  To install permanently: ./Scripts/install.sh"
