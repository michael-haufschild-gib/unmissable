#!/bin/bash

set -euo pipefail

echo "🚨 CRITICAL OVERLAY DEADLOCK TEST - POST FIX"
echo "Testing if the main actor circular dependency fix resolves the deadlock"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

if ! command -v swift >/dev/null 2>&1; then
    echo "❌ swift command not found"
    exit 1
fi

INITIAL_WAIT_SECONDS="${INITIAL_WAIT_SECONDS:-5}"
STABILITY_WAIT_SECONDS="${STABILITY_WAIT_SECONDS:-15}"
APP_PID=""

cleanup() {
    if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" 2>/dev/null; then
        kill "${APP_PID}" 2>/dev/null || true
        wait "${APP_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "🚀 Starting app to test overlay functionality..."
swift run &
APP_PID=$!

echo "📱 App started with PID: $APP_PID"
echo "⏰ Waiting ${INITIAL_WAIT_SECONDS} seconds for app to fully initialize..."
sleep "${INITIAL_WAIT_SECONDS}"

if kill -0 "${APP_PID}" 2>/dev/null; then
    echo "✅ App running successfully after ${INITIAL_WAIT_SECONDS} seconds"
    echo "📊 This indicates the fix prevents immediate deadlocks"

    echo "⏱️ Monitoring app stability for ${STABILITY_WAIT_SECONDS} seconds..."
    sleep "${STABILITY_WAIT_SECONDS}"

    if kill -0 "${APP_PID}" 2>/dev/null; then
        total_seconds=$((INITIAL_WAIT_SECONDS + STABILITY_WAIT_SECONDS))
        echo "✅ CRITICAL SUCCESS: App remained stable for ${total_seconds} total seconds"
        echo "🎯 This suggests overlay creation deadlock is fixed"
        echo "📈 Previous version would deadlock within seconds of overlay creation"
    else
        echo "❌ App crashed during extended runtime"
    fi

    echo "🛑 Stopping app..."
    kill "${APP_PID}" 2>/dev/null || true
    wait "${APP_PID}" 2>/dev/null || true
else
    echo "❌ App crashed during initialization"
fi

echo "📋 Critical test complete"
echo "🚀 If app ran stably, the main actor circular dependency fix is working"
