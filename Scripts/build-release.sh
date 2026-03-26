#!/bin/bash

# Release build script for Unmissable
# Creates a distributable .app bundle without requiring Apple Developer account

set -euo pipefail

# Configuration
APP_NAME="Unmissable"
BUNDLE_ID="com.unmissable.app"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build/release"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
cd "$PROJECT_DIR"

echo "🏗️  Building ${APP_NAME} for release..."

# Clean previous app bundle
echo "🧹  Cleaning previous app bundle..."
rm -rf "${APP_BUNDLE}"

# Build with Swift Package Manager in release mode
echo "📦  Building with Swift Package Manager..."
swift build --configuration release

# Create app bundle structure
echo "📁  Creating app bundle structure..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
echo "📋  Copying executable..."
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/"

# Copy Info.plist
echo "📄  Copying Info.plist..."
cp "${PROJECT_DIR}/Info.plist" "${CONTENTS_DIR}/"

# Copy resources if they exist
if [ -d "${PROJECT_DIR}/Sources/${APP_NAME}/Resources" ] && [ "$(ls -A "${PROJECT_DIR}/Sources/${APP_NAME}/Resources" 2>/dev/null)" ]; then
    echo "📦  Copying resources..."
    cp -R "${PROJECT_DIR}/Sources/${APP_NAME}/Resources/"* "${RESOURCES_DIR}/"
else
    echo "📦  No resources directory found, skipping..."
fi

# Copy Config.plist if it exists (OAuth configuration)
if [ -f "${PROJECT_DIR}/Config.plist" ]; then
    echo "⚙️  Copying configuration..."
    cp "${PROJECT_DIR}/Config.plist" "${RESOURCES_DIR}/"
else
    echo "⚠️  Config.plist not found - app may not work without OAuth configuration"
fi

# Make executable
echo "🔧  Setting executable permissions..."
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Code sign with ad-hoc signature (self-signed, no developer account required)
echo "✍️  Code signing with ad-hoc signature..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# Verify the bundle
echo "✅  Verifying app bundle..."
if [ -x "${MACOS_DIR}/${APP_NAME}" ] && [ -f "${CONTENTS_DIR}/Info.plist" ]; then
    echo "✅  App bundle created successfully!"
    echo "📦  Location: ${APP_BUNDLE}"
    echo ""
    echo "📋  Installation instructions:"
    echo "   1. Move ${APP_BUNDLE} to /Applications/"
    echo "   2. Open System Settings > General > Login Items"
    echo "   3. Add ${APP_NAME} to login items"
    echo ""
    echo "🔍  Bundle contents:"
    ls -la "${APP_BUNDLE}/Contents/"
    echo ""
    ls -la "${MACOS_DIR}/"
    echo ""
    echo "✅  Code signature verification:"
    codesign -dv "${APP_BUNDLE}"
else
    echo "❌  App bundle verification failed"
    exit 1
fi

echo ""
echo "🎉  Release build complete!"
