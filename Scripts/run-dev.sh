#!/bin/bash

# Development launch script for Unmissable
# Builds debug, assembles a .app bundle, and opens it.
# Unlike `swift run`, this creates a proper bundle so UNUserNotificationCenter
# and Sparkle work correctly.

set -euo pipefail

APP_NAME="Unmissable"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build/arm64-apple-macosx/debug"
APP_BUNDLE="${PROJECT_DIR}/.build/debug/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
cd "$PROJECT_DIR"

# Kill any running instance
pkill -f "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

echo "Building ${APP_NAME} (debug)..."
swift build

echo "Assembling .app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Executable
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Info.plist
cp "${PROJECT_DIR}/Info.plist" "${CONTENTS_DIR}/"

# Resources
if [ -d "${PROJECT_DIR}/Sources/${APP_NAME}/Resources" ] && [ "$(ls -A "${PROJECT_DIR}/Sources/${APP_NAME}/Resources" 2>/dev/null)" ]; then
    cp -R "${PROJECT_DIR}/Sources/${APP_NAME}/Resources/"* "${RESOURCES_DIR}/"
fi

# Config.plist (OAuth)
if [ -f "${PROJECT_DIR}/Config.plist" ]; then
    cp "${PROJECT_DIR}/Config.plist" "${RESOURCES_DIR}/"
fi

# Ad-hoc sign
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null

echo "Launching ${APP_NAME}..."
echo "Deep diagnostics: enabled (debug build)"
echo "Console.app filter: subsystem=com.unmissable.app category=Diagnostics"
open "${APP_BUNDLE}"
