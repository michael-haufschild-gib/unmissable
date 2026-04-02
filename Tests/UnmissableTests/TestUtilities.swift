import Foundation
@testable import Unmissable
import XCTest

// MARK: - Test Utilities for Comprehensive Testing

/// Centralized test utilities for creating test data, mocking services, and testing async operations
enum TestUtilities {
    // MARK: - Test Data Creation

    static func createTestEvent(
        id: String = "test-event-\(UUID())",
        title: String = "Test Meeting",
        startDate: Date = Date().addingTimeInterval(300), // 5 minutes from now
        endDate: Date? = nil,
        organizer: String? = "test@example.com",
        calendarId: String = "primary",
        links: [URL] = [],
        provider: Provider? = nil,
        snoozeUntil: Date? = nil,
        autoJoinEnabled: Bool = false,
        timezone: String = "UTC"
    ) -> Event {
        let actualEndDate = endDate ?? startDate.addingTimeInterval(3600) // 1 hour default

        return Event(
            id: id,
            title: title,
            startDate: startDate,
            endDate: actualEndDate,
            organizer: organizer,
            isAllDay: false,
            calendarId: calendarId,
            timezone: timezone,
            links: links,
            provider: provider,
            snoozeUntil: snoozeUntil,
            autoJoinEnabled: autoJoinEnabled,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static func createMeetingEvent(
        provider: Provider = .meet,
        startDate: Date = Date().addingTimeInterval(300)
    ) -> Event {
        // swiftlint:disable force_unwrapping
        // Test-only compile-time constant URLs.
        let links: [URL] = switch provider {
        case .meet:
            [URL(string: "https://meet.google.com/abc-defg-hij")!]

        case .zoom:
            [URL(string: "https://zoom.us/j/123456789")!]

        case .teams:
            [URL(string: "https://teams.microsoft.com/l/meetup-join/abc123")!]

        case .webex:
            [URL(string: "https://example.webex.com/meet/123")!]

        case .generic:
            [URL(string: "https://example.com/meeting")!]
        }
        // swiftlint:enable force_unwrapping

        return createTestEvent(
            title: "\(provider.rawValue.capitalized) Meeting",
            startDate: startDate,
            links: links,
            provider: provider
        )
    }

    static func createPastEvent() -> Event {
        createTestEvent(
            title: "Past Meeting",
            startDate: Date().addingTimeInterval(-3600), // 1 hour ago
            endDate: Date().addingTimeInterval(-1800) // 30 minutes ago
        )
    }

    static func createAllDayEvent() -> Event {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        return Event(
            id: "all-day-\(UUID())",
            title: "All Day Event",
            startDate: startOfDay,
            endDate: startOfDay.addingTimeInterval(24 * 60 * 60), // 24 hours
            organizer: nil,
            isAllDay: true,
            calendarId: "primary",
            timezone: "UTC",
            links: [],
            provider: nil,
            snoozeUntil: nil,
            autoJoinEnabled: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static func createCalendarInfo(
        id: String = "test-calendar-\(UUID())",
        name: String = "Test Calendar",
        isSelected: Bool = true,
        isPrimary: Bool = false
    ) -> CalendarInfo {
        CalendarInfo(
            id: id,
            name: name,
            description: "Test calendar for unit tests",
            isSelected: isSelected,
            isPrimary: isPrimary,
            colorHex: "#1a73e8",
            lastSyncAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - Mock Services

    /// Type alias for PreferencesManager used in tests
    /// PreferencesManager is final, so we use the real class with test extensions
    typealias MockPreferencesManager = PreferencesManager

    /// Factory to create a PreferencesManager with an isolated UserDefaults suite
    @MainActor
    static func createTestPreferencesManager() -> PreferencesManager {
        let suiteName = "com.unmissable.test.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)! // swiftlint:disable:this force_unwrapping
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: ThemeManager())
        // Set test-specific defaults
        prefs.setDefaultAlertMinutes(1)
        prefs.setUseLengthBasedTiming(false)
        prefs.setShortMeetingAlertMinutes(1)
        prefs.setMediumMeetingAlertMinutes(2)
        prefs.setLongMeetingAlertMinutes(5)
        prefs.setOverlayShowMinutesBefore(2)
        prefs.setPlayAlertSound(true)
        prefs.setAutoJoinEnabled(false)
        prefs.setShowOnAllDisplays(true)
        prefs.setOverrideFocusMode(true)
        return prefs
    }
}

// MARK: - Test Accessors for PreferencesManager

extension PreferencesManager {
    /// Test accessors for easy modification in tests
    var testDefaultAlertMinutes: Int {
        get { defaultAlertMinutes }
        set { setDefaultAlertMinutes(newValue) }
    }

    var testUseLengthBasedTiming: Bool {
        get { useLengthBasedTiming }
        set { setUseLengthBasedTiming(newValue) }
    }

    var testOverlayShowMinutesBefore: Int {
        get { overlayShowMinutesBefore }
        set { setOverlayShowMinutesBefore(newValue) }
    }

    var testSoundEnabled: Bool {
        get { soundEnabled }
        set { setPlayAlertSound(newValue) }
    }

    var testAutoJoinEnabled: Bool {
        get { autoJoinEnabled }
        set { setAutoJoinEnabled(newValue) }
    }

    var testShowOnAllDisplays: Bool {
        get { showOnAllDisplays }
        set { setShowOnAllDisplays(newValue) }
    }

    var testOverrideFocusMode: Bool {
        get { overrideFocusMode }
        set { setOverrideFocusMode(newValue) }
    }
}

// MARK: - Test Extensions for EventScheduler

extension EventScheduler {
    /// Returns true if a snooze alert is currently scheduled
    var snoozeScheduled: Bool {
        scheduledAlerts.contains { alert in
            if case .snooze = alert.alertType { return true }
            return false
        }
    }

    /// Returns the most recently scheduled snooze duration in minutes
    var snoozeMinutes: Int? {
        for alert in scheduledAlerts.reversed() {
            if case let .snooze(until) = alert.alertType {
                // Use ceil for future intervals so assertions don't intermittently
                // read N-1 minutes due sub-second execution delays.
                let minutesUntilSnooze = until.timeIntervalSinceNow / 60
                return minutesUntilSnooze >= 0
                    ? Int(ceil(minutesUntilSnooze))
                    : Int(floor(minutesUntilSnooze))
            }
        }
        return nil
    }

    /// Returns the event associated with the most recent snooze
    var snoozeEvent: Event? {
        for alert in scheduledAlerts.reversed() {
            if case .snooze = alert.alertType {
                return alert.event
            }
        }
        return nil
    }

    /// Returns the snooze trigger time
    var snoozeTime: Date? {
        for alert in scheduledAlerts.reversed() {
            if case .snooze = alert.alertType {
                return alert.triggerDate
            }
        }
        return nil
    }

    /// Clears all scheduled alerts (for testing)
    func reset() {
        scheduledAlerts.removeAll()
    }
}

extension TestUtilities {
    // MARK: - Async Testing Utilities

    /// Wait for async operations with timeout
    static func waitForAsync(
        timeout: TimeInterval = 5.0,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if await condition() {
                return
            }
            // swiftlint:disable:next no_raw_task_sleep_in_tests - this IS the polling infrastructure
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        throw XCTestError(.timeoutWhileWaiting)
    }

    // waitForPublished removed - use waitForAsync with a condition closure instead
    // The Published.Publisher async sequence has Sendable issues in Swift 6

    // MARK: - Memory Testing

    /// Test for memory leaks
    static func testForMemoryLeaks(
        instance: @autoclosure () -> (some AnyObject)?,
        after: () throws -> Void,
        timeout: TimeInterval = 5.0
    ) throws {
        weak var weakInstance: AnyObject?
        weakInstance = instance()

        try after()

        // Force garbage collection
        for _ in 0 ..< 3 {
            autoreleasepool {
                _ = Array(repeating: 0, count: 1000)
            }
        }

        let startTime = Date()
        while weakInstance != nil, Date().timeIntervalSince(startTime) < timeout {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        XCTAssertNil(weakInstance, "Memory leak detected: instance was not deallocated")
    }

    // MARK: - UI Testing Utilities

    /// Create test environment for SwiftUI views
    static func createTestEnvironment() -> CustomDesign {
        // Return a consistent design for testing
        CustomDesign.design(for: .light) // Use light theme for consistent testing
    }

    // MARK: - Performance Testing

    /// Measure execution time of operations
    static func measureTime<T>(
        operation: () throws -> T
    ) rethrows -> (result: T, time: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        return (result, timeElapsed)
    }

    /// Measure async execution time
    static func measureTimeAsync<T: Sendable>(
        operation: @Sendable () async throws -> T
    ) async rethrows -> (result: T, time: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        return (result, timeElapsed)
    }
}

// MARK: - Helper Extensions

extension XCTestCase {
    /// Wait for expectation with async block
    func waitForAsync(
        timeout: TimeInterval = 5.0,
        _ block: @escaping @Sendable () async -> Void
    ) {
        let expectation = expectation(description: "Async operation")

        Task {
            await block()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: timeout)
    }

    /// Assert that an async operation throws an error
    func assertThrowsErrorAsync(
        _ operation: () async throws -> some Any,
        _ errorHandler: (Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected operation to throw an error")
        } catch {
            errorHandler(error)
        }
    }
}
