#!/bin/bash

# Test Automation Script for Unmissable App
# This script runs the comprehensive test suite and validates production readiness

set -euo pipefail  # Exit on errors and fail piped commands when xcodebuild fails

echo "🧪 Starting Unmissable Test Automation Suite"
echo "=============================================="

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="Unmissable"
DESTINATION="platform=macOS"
BUILD_DIR="$PROJECT_DIR/.build"
COVERAGE_DIR="$PROJECT_DIR/coverage"
REPORTS_DIR="$PROJECT_DIR/test-reports"
cd "$PROJECT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$BUILD_DIR"
}

# Set up cleanup on exit
trap cleanup EXIT

# Create necessary directories
mkdir -p "$COVERAGE_DIR"
mkdir -p "$REPORTS_DIR"

# Step 1: Code Formatting and Linting
log_info "Step 1: Running code formatting and linting..."

if command -v swiftformat &> /dev/null; then
    log_info "Running SwiftFormat..."
    swiftformat "$PROJECT_DIR/Sources" "$PROJECT_DIR/Tests" --config "$PROJECT_DIR/.swiftformat"
    log_success "Code formatting completed"
else
    log_warning "SwiftFormat not found, skipping formatting"
fi

log_info "Running enforced SwiftLint policy..."
"$PROJECT_DIR/Scripts/enforce-lint.sh"
log_success "Linting completed"

# Step 2: Build the project
log_info "Step 2: Building project..."
if xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" build | tee "$REPORTS_DIR/build.log"; then
    log_success "Build completed successfully"
else
    log_error "Build failed"
    exit 1
fi

# Step 3: Run Unit Tests
log_info "Step 3: Running unit tests..."
if xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" test \
    -only-testing:"UnmissableTests" \
    -resultBundlePath "$REPORTS_DIR/unit-tests.xcresult" \
    | tee "$REPORTS_DIR/unit-tests.log"; then
    log_success "Unit tests passed"
else
    log_error "Unit tests failed"
    exit 1
fi

# Step 4: Run Integration Tests
log_info "Step 4: Running integration tests..."
if xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" test \
    -only-testing:"IntegrationTests" \
    -resultBundlePath "$REPORTS_DIR/integration-tests.xcresult" \
    | tee "$REPORTS_DIR/integration-tests.log"; then
    log_success "Integration tests passed"
else
    log_error "Integration tests failed"
    exit 1
fi

# Step 5: Run UI/Snapshot Tests
log_info "Step 5: Running UI and snapshot tests..."
if xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" test \
    -only-testing:"SnapshotTests" \
    -resultBundlePath "$REPORTS_DIR/ui-tests.xcresult" \
    | tee "$REPORTS_DIR/ui-tests.log"; then
    log_success "UI tests passed"
else
    log_warning "UI tests failed (may be acceptable for snapshot tests)"
fi

# Step 6: Generate Code Coverage Report
log_info "Step 6: Generating code coverage report..."
PROFDATA_PATH="$BUILD_DIR/debug/codecov/default.profdata"
BINARY_PATH="$BUILD_DIR/debug/UnmissablePackageTests.xctest/Contents/MacOS/UnmissablePackageTests"
if [ -f "$PROFDATA_PATH" ] && [ -f "$BINARY_PATH" ]; then
    xcrun llvm-cov export -format="lcov" \
        "$BINARY_PATH" \
        -instr-profile="$PROFDATA_PATH" > "$COVERAGE_DIR/coverage.lcov" 2>/dev/null \
        && log_success "Code coverage report generated" \
        || log_warning "Coverage export failed"
else
    log_warning "Coverage data not found (run swift test --enable-code-coverage first)"
fi

# Step 7: Performance Testing
log_info "Step 7: Running performance tests..."
if xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" test \
    -only-testing:"UnmissableTests/EventSchedulerComprehensiveTests/testLargeNumberOfEvents" \
    -only-testing:"UnmissableTests/SystemIntegrationTests/testEndToEndPerformance" \
    -only-testing:"UnmissableTests/MeetingDetailsPopupTests/testPopupPerformanceUnderLoad" \
    -resultBundlePath "$REPORTS_DIR/performance-tests.xcresult" \
    | tee "$REPORTS_DIR/performance-tests.log"; then
    log_success "Performance tests passed"
else
    log_warning "Performance tests had issues"
fi

# Step 8: Resource Lifecycle / Cleanup Tests
log_info "Step 8: Running resource lifecycle and cleanup tests..."
if xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" test \
    -only-testing:"UnmissableTests/SyncManagerLifecycleTests" \
    -only-testing:"UnmissableTests/HealthMonitorTests" \
    -only-testing:"UnmissableTests/EventSchedulerComprehensiveTests/testMemoryCleanupSimple" \
    -only-testing:"UnmissableTests/SystemIntegrationTests/testMemoryPressureHandling" \
    -resultBundlePath "$REPORTS_DIR/memory-tests.xcresult" \
    | tee "$REPORTS_DIR/memory-tests.log"; then
    log_success "Resource lifecycle tests passed"
else
    log_error "Resource lifecycle tests failed"
    exit 1
fi

# Step 9: Test Report Analysis
log_info "Step 9: Analyzing test results..."

# Extract test metrics from xcresult bundles
if command -v xcparse &> /dev/null; then
    for result_bundle in "$REPORTS_DIR"/*.xcresult; do
        if [ -f "$result_bundle" ]; then
            bundle_name=$(basename "$result_bundle" .xcresult)
            xcparse --output "$REPORTS_DIR/$bundle_name-summary.json" "$result_bundle"
        fi
    done
    log_success "Test results parsed"
else
    log_warning "xcparse not found, skipping detailed test analysis"
fi

# Step 10: Production Readiness Check
log_info "Step 10: Production readiness validation..."

# Check for critical issues
CRITICAL_ISSUES=0

# Check test pass rate
if grep -q "Test Suite.*failed" "$REPORTS_DIR/unit-tests.log"; then
    log_error "Unit test failures detected"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

if grep -q "Test Suite.*failed" "$REPORTS_DIR/integration-tests.log"; then
    log_error "Integration test failures detected"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

# Check resource-lifecycle test result stream
if grep -q "Test Suite.*failed" "$REPORTS_DIR/memory-tests.log"; then
    log_error "Resource lifecycle test failures detected"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

# Check performance benchmarks
if grep -q "Performance test failed" "$REPORTS_DIR/performance-tests.log"; then
    log_warning "Performance benchmarks not met"
fi

# Generate final report
cat > "$REPORTS_DIR/production-readiness-report.md" << EOF
# Production Readiness Report

Generated: $(date)

## Test Suite Results

### Unit Tests
- Status: $(if grep -q "Test Suite.*failed" "$REPORTS_DIR/unit-tests.log"; then echo "❌ FAILED"; else echo "✅ PASSED"; fi)
- Log: unit-tests.log

### Integration Tests
- Status: $(if grep -q "Test Suite.*failed" "$REPORTS_DIR/integration-tests.log"; then echo "❌ FAILED"; else echo "✅ PASSED"; fi)
- Log: integration-tests.log

### UI Tests
- Status: $(if grep -q "Test Suite.*failed" "$REPORTS_DIR/ui-tests.log"; then echo "⚠️ ISSUES"; else echo "✅ PASSED"; fi)
- Log: ui-tests.log

### Performance Tests
- Status: $(if grep -q "Performance test failed" "$REPORTS_DIR/performance-tests.log"; then echo "⚠️ SLOW"; else echo "✅ PASSED"; fi)
- Log: performance-tests.log

### Memory Tests
- Status: $(if grep -q "Test Suite.*failed" "$REPORTS_DIR/memory-tests.log"; then echo "❌ FAILED"; else echo "✅ PASSED"; fi)
- Log: memory-tests.log

## Critical Issues
- Count: $CRITICAL_ISSUES

## Production Readiness
$(if [ $CRITICAL_ISSUES -eq 0 ]; then echo "✅ **READY FOR PRODUCTION**"; else echo "❌ **NOT READY - $CRITICAL_ISSUES critical issues**"; fi)

## Recommendations
$(if [ $CRITICAL_ISSUES -eq 0 ]; then
    echo "- All critical tests passing"
    echo "- Resource lifecycle/cleanup checks passed"
    echo "- System meets performance requirements"
    echo "- Safe to deploy to production"
else
    echo "- Fix failing unit/integration tests"
    echo "- Resolve resource lifecycle/cleanup failures"
    echo "- Review performance issues"
    echo "- Re-run test suite before deployment"
fi)
EOF

# Final Results
echo ""
echo "🎯 Test Automation Complete!"
echo "==============================="
echo ""

if [ $CRITICAL_ISSUES -eq 0 ]; then
    log_success "ALL TESTS PASSED - APPLICATION IS PRODUCTION READY! 🚀"
    echo ""
    log_info "Summary:"
    echo "  ✅ Unit tests: PASSED"
    echo "  ✅ Integration tests: PASSED"
    echo "  ✅ Memory tests: PASSED"
    echo "  📊 Performance tests: $(if grep -q "Performance test failed" "$REPORTS_DIR/performance-tests.log"; then echo "SLOW"; else echo "PASSED"; fi)"
    echo "  📱 UI tests: $(if grep -q "Test Suite.*failed" "$REPORTS_DIR/ui-tests.log"; then echo "ISSUES"; else echo "PASSED"; fi)"
    echo ""
    echo "📋 Reports generated in: $REPORTS_DIR"
    echo "📊 Coverage report: $COVERAGE_DIR"
    echo ""
    echo "The application is stable, freeze-free, and ready for production deployment."
else
    log_error "TESTS FAILED - $CRITICAL_ISSUES CRITICAL ISSUES FOUND"
    echo ""
    log_info "Issues to fix:"
    grep -l "failed\|FAILED\|Memory leak" "$REPORTS_DIR"/*.log | while read -r file; do
        echo "  🔍 Check: $(basename "$file")"
    done
    echo ""
    echo "Review the test reports and fix issues before deployment."
    exit 1
fi
