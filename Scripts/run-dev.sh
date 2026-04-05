#!/bin/bash

# Development launch script for Unmissable
# Builds debug and launches via xcodebuild, creating a proper .app bundle
# so UNUserNotificationCenter and other bundle-only APIs work correctly.

set -euo pipefail

APP_NAME="Unmissable"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEPROJ="$PROJECT_DIR/Unmissable.xcodeproj"
SCHEME="Unmissable"
HOST_ARCH="$(uname -m)"
DESTINATION="${DESTINATION:-platform=macOS,arch=${HOST_ARCH}}"
cd "$PROJECT_DIR"

# Kill any running instance
pkill -x "${APP_NAME}" 2>/dev/null || true

echo "Building ${APP_NAME} (debug)..."
xcodebuild build \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -quiet

# Find the built .app in DerivedData
DERIVED_DATA_DIR=$(xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/ { print $3; exit }')
APP_BUNDLE="${DERIVED_DATA_DIR}/${APP_NAME}.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: Built app not found at $APP_BUNDLE"
    exit 1
fi

# Copy Config.plist if it exists (OAuth configuration)
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"
if [ -f "${PROJECT_DIR}/Config.plist" ]; then
    mkdir -p "$RESOURCES_DIR"
    cp "${PROJECT_DIR}/Config.plist" "${RESOURCES_DIR}/"
fi

echo "Launching ${APP_NAME}..."
echo "Deep diagnostics: enabled (debug build)"
echo "Console.app filter: subsystem=com.unmissable.app category=Diagnostics"
open "$APP_BUNDLE"
