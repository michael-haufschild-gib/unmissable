import Foundation
@testable import Unmissable
import XCTest

/// Centralized test data cleanup utility to ensure all tests clean up after themselves
@MainActor
class TestDataCleanup {
    static let shared = TestDataCleanup()
    private let databaseManager = DatabaseManager.shared

    private init() {}

    /// Comprehensive cleanup of all test data patterns
    /// This should be called in setUp() and tearDown() of all tests that use the database
    func cleanupAllTestData() async throws {
        // Clean up by ID patterns - comprehensive patterns to catch all test events
        let idPatterns = [
            "test", "perf-test", "memory-test", "fetch-perf", "test-save", "test-event",
            "e2e-test", "started-test", "db-test", "integration-test", "deadlock-test",
            "timer-test", "window-server", "accessibility-test", "theme-test",
            "snooze-test", "overlay-test", "schedule-test", "rapid-test", "focus-test",
            "notification-test", "ui-test", "system-test",
        ]

        for pattern in idPatterns {
            try await databaseManager.deleteTestEvents(withIdPattern: pattern)
        }

        // Clean up by common test title patterns
        let titlePatterns = [
            "Test Meeting", "Memory Test", "Performance Test", "Integration Test",
            "Deadlock Test", "Timer Test", "Window Server", "End-to-End Test",
            "Database Test", "Accessibility Test", "Theme Test", "Snooze Test",
            "Upcoming Meeting", "Updated Title", "Meeting 0", "Meeting 1", "Meeting 2",
            "Meeting 3", "Meeting 4", "Meeting with", "Sample Meeting", "Mock Meeting",
            "Debug Meeting", "Unit Test", "Overlay Test", "Schedule Test", "Focus Test",
        ]

        for pattern in titlePatterns {
            try await databaseManager.deleteTestEventsByTitle(withPattern: pattern)
        }

        // Clean up test calendars
        try await databaseManager.deleteTestCalendars(withNamePattern: "Test Calendar")
        try await databaseManager.deleteTestCalendars(withNamePattern: "Mock Calendar")
        try await databaseManager.deleteTestCalendars(withNamePattern: "Debug Calendar")
    }

    /// Quick cleanup for tests that only use specific patterns
    func cleanupTestEvents(withIdPattern pattern: String) async throws {
        try await databaseManager.deleteTestEvents(withIdPattern: pattern)
    }

    /// Quick cleanup for tests that only use specific title patterns
    func cleanupTestEvents(withTitlePattern pattern: String) async throws {
        try await databaseManager.deleteTestEventsByTitle(withPattern: pattern)
    }
}

/// Test base class that automatically handles cleanup
/// Use this as a base class for any tests that interact with the database
@MainActor
class DatabaseTestCase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        // Clean up any existing test data before the test starts
        try await TestDataCleanup.shared.cleanupAllTestData()
    }

    override func tearDown() async throws {
        // Clean up test data after each test completes
        try await TestDataCleanup.shared.cleanupAllTestData()
        try await super.tearDown()
    }
}
