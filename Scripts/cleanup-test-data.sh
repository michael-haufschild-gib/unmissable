#!/bin/bash

# Test Data Cleanup Script - Removes only test events and calendars
# This script preserves real user data while cleaning up test artifacts

echo "🧹 Starting targeted test data cleanup..."

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="$HOME/Library/Application Support/Unmissable/unmissable.db"

if [ -f "$DB_PATH" ]; then
    echo "📁 Found database at $DB_PATH"
    echo "📊 Before cleanup:"

    # Show current state
    EVENT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM events;")
    CALENDAR_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM calendars;")
    echo "   - Total events: $EVENT_COUNT"
    echo "   - Total calendars: $CALENDAR_COUNT"

    echo "🗑️  Removing test events and calendars..."

    # Remove test events by ID patterns (avoid broad %test% matches to preserve real IDs)
    sqlite3 "$DB_PATH" << EOSQL
DELETE FROM events WHERE
    id LIKE 'test-%' OR
    id LIKE 'test_%' OR
    id LIKE 'perf-test-%' OR
    id LIKE 'memory-test-%' OR
    id LIKE 'fetch-perf-%' OR
    id LIKE 'test-save-%' OR
    id LIKE 'test-event-%' OR
    id LIKE 'e2e-test-%' OR
    id LIKE 'started-test-%' OR
    id LIKE 'db-test-%' OR
    id LIKE 'integration-test-%' OR
    id LIKE 'deadlock-test-%' OR
    id LIKE 'timer-test-%' OR
    id LIKE 'window-server-%' OR
    id LIKE 'accessibility-test-%' OR
    id LIKE 'theme-test-%' OR
    id LIKE 'snooze-test-%' OR
    id LIKE 'overlay-test-%' OR
    id LIKE 'schedule-test-%';
EOSQL

    # Remove test events by title patterns (only explicit test naming conventions)
    sqlite3 "$DB_PATH" << EOSQL
DELETE FROM events WHERE
    title = 'Test Meeting' OR
    title LIKE 'Test Meeting %' OR
    title LIKE '% Test Meeting' OR
    title LIKE '%Memory Test%' OR
    title LIKE '%Performance Test%' OR
    title LIKE '%Integration Test%' OR
    title LIKE '%Deadlock Test%' OR
    title LIKE '%Timer Test%' OR
    title LIKE '%Window Server Test%' OR
    title LIKE '%End-to-End Test%' OR
    title LIKE '%Database Test%' OR
    title LIKE '%Accessibility Test%' OR
    title LIKE '%Theme Test%' OR
    title LIKE '%Snooze Test%' OR
    title LIKE '%Overlay Test%' OR
    title LIKE '%Schedule Test%';
EOSQL

    # Remove test calendars by explicit test naming conventions
    sqlite3 "$DB_PATH" << EOSQL
DELETE FROM calendars WHERE
    name = 'Test Calendar' OR
    name LIKE 'Test Calendar %' OR
    name LIKE '% Test Calendar' OR
    name LIKE '%Test Calendar%' OR
    name LIKE 'Integration Test Calendar%' OR
    name LIKE 'Performance Test Calendar%';
EOSQL

    echo "📊 After cleanup:"

    # Show final state
    NEW_EVENT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM events;")
    NEW_CALENDAR_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM calendars;")
    REMOVED_EVENTS=$((EVENT_COUNT - NEW_EVENT_COUNT))
    REMOVED_CALENDARS=$((CALENDAR_COUNT - NEW_CALENDAR_COUNT))

    echo "   - Remaining events: $NEW_EVENT_COUNT"
    echo "   - Remaining calendars: $NEW_CALENDAR_COUNT"
    echo "   - Removed events: $REMOVED_EVENTS"
    echo "   - Removed calendars: $REMOVED_CALENDARS"

    echo "✅ Database cleanup completed successfully!"

else
    echo "✅ No database found - nothing to clean"
fi

# Clean up any temporary test files
echo "🗑️  Cleaning temporary test files..."
find "$PROJECT_DIR" -name "*.tmp" -delete 2>/dev/null || true
find "$PROJECT_DIR" -name "*test*.db" -delete 2>/dev/null || true
find "$PROJECT_DIR" -name "*debug*.log" -delete 2>/dev/null || true

echo "✅ Test data cleanup completed successfully!"
echo ""
echo "📋 Summary:"
echo "   - Cleaned test events from database (preserving real events)"
echo "   - Cleaned test calendars from database"
echo "   - Cleaned temporary test files"
echo ""
echo "🎯 Production app is now clean of test data while preserving user data"
