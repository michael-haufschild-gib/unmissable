#!/bin/bash

set -euo pipefail

echo "🔬 MANUAL OVERLAY DEADLOCK TEST"
echo "This script will test the actual overlay deadlock by running the app"
echo "and triggering overlay creation directly"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

if ! command -v swift >/dev/null 2>&1; then
    echo "❌ swift command not found"
    exit 1
fi

INITIAL_WAIT_SECONDS="${INITIAL_WAIT_SECONDS:-3}"
STABILITY_WAIT_SECONDS="${STABILITY_WAIT_SECONDS:-10}"
APP_PID=""

cleanup() {
    if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" 2>/dev/null; then
        kill "${APP_PID}" 2>/dev/null || true
        wait "${APP_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "🚀 Starting app in background..."
swift run &
APP_PID=$!

echo "📱 App started with PID: $APP_PID"
echo "⏰ Waiting ${INITIAL_WAIT_SECONDS} seconds for app to initialize..."
sleep "${INITIAL_WAIT_SECONDS}"

echo "🔍 Checking if app is still running..."
if kill -0 "${APP_PID}" 2>/dev/null; then
    echo "✅ App is running successfully"

    echo "⏱️ Letting app run for ${STABILITY_WAIT_SECONDS} seconds to test stability..."
    sleep "${STABILITY_WAIT_SECONDS}"

    if kill -0 "${APP_PID}" 2>/dev/null; then
        echo "✅ App remained stable for ${STABILITY_WAIT_SECONDS} seconds"
        echo "📋 This suggests overlay creation might work in real context"
    else
        echo "❌ App crashed during runtime"
    fi

    echo "🛑 Killing app..."
    kill "${APP_PID}" 2>/dev/null || true
    wait "${APP_PID}" 2>/dev/null || true
else
    echo "❌ App already crashed during startup"
fi

echo "📊 Test complete"
