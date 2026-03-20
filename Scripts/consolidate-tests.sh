#!/bin/bash

# CONSOLIDATED TEST CLEANUP AND MANAGEMENT SCRIPT
# This script removes duplicate/overlapping tests and runs the new consolidated test suite

set -euo pipefail

echo "🧹 CONSOLIDATING TEST SUITE: Removing duplicate and overlapping tests"
echo "======================================================================"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
REMOVAL_APPLIED=false
REMOVED_COUNT=0
TEST_FAILURE=0
SCHEME="Unmissable"
DESTINATION="platform=macOS"

run_xcode_test_cluster() {
    local cluster_name="$1"
    shift

    local test_log
    test_log="$(mktemp -t unmissable-consolidated-tests)"

    if ! xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" test "$@" | tee "$test_log"; then
        echo "❌ ${cluster_name} failed."
        TEST_FAILURE=1
        rm -f "$test_log"
        return
    fi

    if ! grep -Eq "Executed [1-9][0-9]* test" "$test_log"; then
        echo "❌ ${cluster_name} executed zero tests (failing to avoid false confidence)."
        TEST_FAILURE=1
    fi

    rm -f "$test_log"
}

# List of tests to remove (duplicates and overlaps)
TESTS_TO_REMOVE=(
    # Legacy deadlock/reproduction tests consolidated into runtime contract coverage
    "Tests/UnmissableTests/CriticalOverlayDeadlockTest.swift"
    "Tests/UnmissableTests/OverlayDeadlockReproductionTest.swift"
    "Tests/UnmissableTests/OverlayDeadlockSimpleTest.swift"
    "Tests/UnmissableTests/TimerInvalidationDeadlockTest.swift"
    "Tests/UnmissableTests/WindowServerDeadlockTest.swift"
    "Tests/UnmissableTests/AsyncDispatchDeadlockFixTest.swift"
    "Tests/UnmissableTests/DismissDeadlockFixValidationTest.swift"
    "Tests/UnmissableTests/ProductionDismissDeadlockTest.swift"
    "Tests/UnmissableTests/UIInteractionDeadlockTest.swift"
    "Tests/UnmissableTests/EndToEndDeadlockPreventionTests.swift"

    # Overlapping umbrella suites migrated into focused runtime/interaction suites
    "Tests/UnmissableTests/ComprehensiveOverlayTest.swift"
    "Tests/UnmissableTests/OverlayCompleteIntegrationTests.swift"
    "Tests/UnmissableTests/OverlayManagerComprehensiveTests.swift"
    "Tests/UnmissableTests/OverlayManagerIntegrationTests.swift"
    "Tests/UnmissableTests/OverlayFunctionalityIntegrationTests.swift"
    "Tests/UnmissableTests/OverlayBugReproductionTests.swift"
    "Tests/UnmissableTests/OverlaySnapshotTests.swift"

    # Migration-era timer suites migrated into runtime/interaction suites
    "Tests/UnmissableTests/OverlayTimerLogicTests.swift"
    "Tests/UnmissableTests/OverlayTimerFixValidationTests.swift"
    "Tests/UnmissableTests/CountdownTimerMigrationTests.swift"
    "Tests/UnmissableTests/SnoozeTimerMigrationTests.swift"
    "Tests/UnmissableTests/ScheduleTimerMigrationTests.swift"
    "Tests/UnmissableTests/OverlayManagerTimerFixTest.swift"
    "Tests/UnmissableTests/TimerMigrationTestHelpers.swift"

    # UI/Component tests that overlap
    "Tests/UnmissableTests/ComprehensiveUICallbackTest.swift"
    "Tests/UnmissableTests/UIComponentComprehensiveTests.swift"
    "Tests/UnmissableTests/OverlayUIInteractionValidationTests.swift"

    # Redundant snooze tests
    "Tests/UnmissableTests/ProductionSnoozeEndToEndTest.swift"
)

echo "📋 Tests scheduled for removal:"
for test in "${TESTS_TO_REMOVE[@]}"; do
    if [ -f "$test" ]; then
        echo "  ✓ $test"
    else
        echo "  ⚠️  $test (already removed)"
    fi
done

echo ""
read -p "🤔 Do you want to proceed with removing these duplicate tests? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing duplicate tests..."
    REMOVAL_APPLIED=true

    for test in "${TESTS_TO_REMOVE[@]}"; do
        if [ -f "$test" ]; then
            rm "$test"
            REMOVED_COUNT=$((REMOVED_COUNT + 1))
            echo "  ✅ Removed: $test"
        fi
    done

    echo ""
    echo "✅ Duplicate test removal completed! ($REMOVED_COUNT file(s) removed)"
else
    echo "❌ Test removal cancelled."
    echo "💡 You can review the list above and remove tests manually if preferred."
fi

echo ""
echo "🧪 REMAINING CORE TESTS AFTER CONSOLIDATION:"
echo "=============================================="

# List core tests that should remain
CORE_TESTS=(
    "Tests/UnmissableTests/OverlayRuntimeContractTests.swift"
    "Tests/UnmissableTests/OverlayAccuracyAndInteractionTests.swift"
    "Tests/UnmissableTests/OverlaySnoozeAndDismissTests.swift"
    "Tests/UnmissableTests/SystemIntegrationTests.swift"
    "Tests/UnmissableTests/AppStateDisconnectCleanupTests.swift"
    "Tests/UnmissableTests/EventSchedulerSnoozePreservationTests.swift"
    "Tests/UnmissableTests/OverlayContentViewTests.swift"
    "Tests/UnmissableTests/StartedMeetingsTests.swift"
    "Tests/UnmissableTests/EventTests.swift"
    "Tests/UnmissableTests/LinkParserTests.swift"
    "Tests/UnmissableTests/AttendeeModelTests.swift"
    "Tests/UnmissableTests/ProviderTests.swift"
    "Tests/UnmissableTests/PreferencesManagerTests.swift"
    "Tests/UnmissableTests/DatabaseManagerComprehensiveTests.swift"
    "Tests/UnmissableTests/EventSchedulerComprehensiveTests.swift"
    "Tests/UnmissableTests/EventFilteringTests.swift"
    "Tests/UnmissableTests/MeetingDetailsEndToEndTests.swift"
    "Tests/UnmissableTests/MeetingDetailsPopupTests.swift"
    "Tests/UnmissableTests/MeetingDetailsUIAutomationTests.swift"
    "Tests/UnmissableTests/TestUtilities.swift"
    "Tests/IntegrationTests/CalendarServiceIntegrationTests.swift"
    "Tests/SnapshotTests/OverlaySnapshotTests.swift"
)

echo "📊 Core test suite (focused and non-overlapping):"
for test in "${CORE_TESTS[@]}"; do
    if [ -f "$test" ]; then
        echo "  ✅ $test"
    else
        echo "  ❌ $test (missing)"
    fi
done

echo ""
echo "🚀 RUNNING CONSOLIDATED TEST SUITE:"
echo "===================================="

echo "🧹 Enforcing lint policy before tests..."
if ! "$PROJECT_DIR/Scripts/enforce-lint.sh"; then
    echo "❌ Lint policy check failed. Resolve lint issues before running consolidated tests."
    exit 1
fi

echo "🔧 Building project..."
if ! swift build; then
    echo "❌ Build failed. Please fix compilation errors before running tests."
    exit 1
fi

echo "✅ Build successful!"
echo ""
echo "🧪 Running runtime overlay contract tests..."
run_xcode_test_cluster \
    "Runtime overlay contract tests" \
    -only-testing:"UnmissableTests/OverlayRuntimeContractTests"

echo ""
echo "🧪 Running consolidated overlay integration test cluster..."
run_xcode_test_cluster \
    "Overlay integration cluster" \
    -only-testing:"UnmissableTests/OverlaySnoozeAndDismissTests" \
    -only-testing:"UnmissableTests/OverlayAccuracyAndInteractionTests" \
    -only-testing:"UnmissableTests/SystemIntegrationTests" \
    -only-testing:"UnmissableTests/AppStateDisconnectCleanupTests" \
    -only-testing:"UnmissableTests/EventSchedulerSnoozePreservationTests"

echo ""
echo "🧪 Running core model and utility tests..."
run_xcode_test_cluster \
    "Core model and utility tests" \
    -only-testing:"UnmissableTests/EventTests" \
    -only-testing:"UnmissableTests/LinkParserTests" \
    -only-testing:"UnmissableTests/AttendeeModelTests" \
    -only-testing:"UnmissableTests/ProviderTests"

if [ $TEST_FAILURE -ne 0 ]; then
    echo "❌ One or more consolidated test runs failed."
fi

echo ""
echo "📋 CONSOLIDATION SUMMARY:"
echo "========================"
if [ "$REMOVAL_APPLIED" = true ]; then
    echo "✅ Removed duplicate/overlapping suites: $REMOVED_COUNT file(s)"
else
    echo "ℹ️  No files removed (cleanup cancelled by user)"
fi
echo "✅ Consolidated coverage now centers on runtime contract + focused overlay suites"
echo "✅ Kept essential model, parsing, integration, and utility tests"
echo ""
echo "🎯 FOCUS: runtime contract correctness + focused integration behavior"
echo "💡 The suite avoids stale umbrella tests while preserving high-value contracts"

if [ $TEST_FAILURE -ne 0 ]; then
    exit 1
fi
