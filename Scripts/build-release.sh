#!/bin/bash

# Release build script for Unmissable
# Creates a distributable .app bundle via xcodebuild archive

set -euo pipefail

# Configuration
APP_NAME="Unmissable"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEPROJ="$PROJECT_DIR/Unmissable.xcodeproj"
SCHEME="Unmissable"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
cd "$PROJECT_DIR"

echo "Building ${APP_NAME} for release..."

# Clean previous build artifacts
echo "Cleaning previous build artifacts..."
rm -rf "${BUILD_DIR}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${BUILD_DIR}"

# Archive — output logged so failures are diagnosable on CI/local
echo "Archiving with xcodebuild (log: ${BUILD_DIR}/archive.log)..."
xcodebuild archive \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    2>&1 | tee "${BUILD_DIR}/archive.log"

# Extract .app from archive
echo "Extracting app bundle from archive..."
ARCHIVED_APP="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
if [ -d "$ARCHIVED_APP" ]; then
    cp -R "$ARCHIVED_APP" "$APP_BUNDLE"
else
    echo "ERROR: Archived app not found at $ARCHIVED_APP"
    exit 1
fi

# Copy Config.plist if it exists (OAuth configuration)
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"
if [ -f "${PROJECT_DIR}/Config.plist" ]; then
    echo "Copying configuration..."
    mkdir -p "$RESOURCES_DIR"
    cp "${PROJECT_DIR}/Config.plist" "${RESOURCES_DIR}/"
else
    echo "WARNING: Config.plist not found - app may not work without OAuth configuration"
fi

# Ad-hoc code sign (no developer account required)
echo "Code signing with ad-hoc signature..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# Verify the bundle
echo "Verifying app bundle..."
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
if [ -x "${MACOS_DIR}/${APP_NAME}" ] && [ -f "${CONTENTS_DIR}/Info.plist" ]; then
    echo "App bundle created successfully!"
    echo "Location: ${APP_BUNDLE}"
    echo ""
    echo "Installation instructions:"
    echo "   1. Move ${APP_BUNDLE} to /Applications/"
    echo "   2. Open System Settings > General > Login Items"
    echo "   3. Add ${APP_NAME} to login items"
    echo ""
    echo "Bundle contents:"
    ls -la "${CONTENTS_DIR}/"
    echo ""
    echo "Code signature verification:"
    codesign -dv "${APP_BUNDLE}"
else
    echo "ERROR: App bundle verification failed"
    exit 1
fi

# Cleanup archive
rm -rf "${BUILD_DIR}"

echo ""
echo "Release build complete!"
