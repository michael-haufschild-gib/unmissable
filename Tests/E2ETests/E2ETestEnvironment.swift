import Foundation
import Testing
@testable import Unmissable

/// Full-stack test environment that wires up the real composition root with a test-scoped database.
/// This enables true end-to-end testing: DB → fetch → schedule → overlay.
@MainActor
final class E2ETestEnvironment {
    let databaseManager: DatabaseManager
    let preferencesManager: PreferencesManager
    let eventScheduler: EventScheduler
    let overlayManager: TestSafeOverlayManager
    let meetingDetailsPopupManager: TestSafeMeetingDetailsPopupManager
    let testClock: TestClock

    private let tempDatabaseURL: URL
    private let userDefaultsSuiteName: String

    init(useTestClock: Bool = true) async throws {
        // Create an isolated temporary database for each test environment
        let tempDir = FileManager.default.temporaryDirectory
        let dbName = "unmissable-e2e-\(UUID().uuidString).db"
        tempDatabaseURL = tempDir.appendingPathComponent(dbName)

        databaseManager = DatabaseManager(databaseURL: tempDatabaseURL)
        guard await databaseManager.isInitialized else {
            throw await E2EError.databaseInitFailed(
                databaseManager.initializationError ?? "Unknown error",
            )
        }

        // Use isolated UserDefaults to avoid cross-test pollution
        userDefaultsSuiteName = "com.unmissable.e2e.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        preferencesManager = PreferencesManager(userDefaults: testDefaults, themeManager: ThemeManager())
        // Set deterministic test defaults
        preferencesManager.setDefaultAlertMinutes(TestConstants.defaultAlertMinutes)
        preferencesManager.setOverlayShowMinutesBefore(TestConstants.overlayShowMinutesBefore)
        preferencesManager.setPlayAlertSound(false)
        preferencesManager.setUseLengthBasedTiming(false)
        preferencesManager.setShowOnAllDisplays(false)
        preferencesManager.setOverrideFocusMode(false)
        preferencesManager.setAutoJoinEnabled(false)
        preferencesManager.setIncludeAllDayEvents(false)

        testClock = TestClock(startTime: Date())
        if useTestClock {
            eventScheduler = EventScheduler(
                preferencesManager: preferencesManager,
                linkParser: LinkParser(),
                sleepForSeconds: testClock.sleepForSeconds,
                now: testClock.nowProvider,
            )
        } else {
            eventScheduler = EventScheduler(
                preferencesManager: preferencesManager,
                linkParser: LinkParser(),
            )
        }
        overlayManager = TestSafeOverlayManager(isTestEnvironment: true)
        meetingDetailsPopupManager = TestSafeMeetingDetailsPopupManager()

        // Wire up the components exactly as the production AppState does
        overlayManager.setEventScheduler(eventScheduler)
    }

    deinit {
        // Clean up temporary database file and isolated UserDefaults suite.
        try? FileManager.default.removeItem(at: tempDatabaseURL)
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
    }

    // MARK: - Database Seeding

    /// Seeds the database with events and returns them for assertion
    func seedEvents(_ events: [Event]) async throws {
        try await databaseManager.saveEvents(events)
    }

    /// Seeds events and computes alerts (missed alerts trigger overlay synchronously).
    /// Does NOT start the monitoring loop by default — most tests use
    /// `showOverlayImmediately` and don't need it. Pass `startMonitoring: true`
    /// for the ~5 tests that need the loop to fire via `waitForOverlay`.
    func seedAndSchedule(
        _ events: [Event],
        startMonitoring: Bool = false,
    ) async throws {
        try await seedEvents(events)
        let upcoming = try await databaseManager.fetchUpcomingEvents(limit: TestConstants.fetchLimit)
        if startMonitoring {
            await eventScheduler.startScheduling(events: upcoming, overlayManager: overlayManager)
        } else {
            // Schedule alerts (fires missed alerts synchronously) but skip
            // the monitoring loop. Callers use showOverlayImmediately instead.
            eventScheduler.scheduleWithoutMonitoring(
                events: upcoming,
                overlayManager: overlayManager,
            )
        }
    }

    /// Seeds calendars into the database
    func seedCalendars(_ calendars: [CalendarInfo]) async throws {
        try await databaseManager.saveCalendars(calendars)
    }

    // MARK: - Fetch Helpers

    func fetchUpcomingEvents(limit: Int = TestConstants.defaultUpcomingLimit) async throws -> [Event] {
        try await databaseManager.fetchUpcomingEvents(limit: limit)
    }

    func fetchStartedMeetings(limit: Int = TestConstants.defaultStartedLimit) async throws -> [Event] {
        try await databaseManager.fetchStartedMeetings(limit: limit)
    }

    func fetchEvents(from start: Date, to end: Date) async throws -> [Event] {
        try await databaseManager.fetchEvents(from: start, to: end)
    }

    // MARK: - Monitoring Loop Helpers

    /// Advances the test clock far enough to fire all pending alerts, then
    /// asserts the overlay is visible. Uses PointFree's TestClock which
    /// suspends the monitoring loop on continuations — no spinning, no starvation.
    ///
    /// - Parameter advanceBy: How far to advance simulated time (default 10 min).
    func waitForOverlay(
        advanceBy: TimeInterval = 600,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async {
        await testClock.advance(bySeconds: advanceBy)
        if !overlayManager.isOverlayVisible {
            let dump = diagnosticDump(context: [
                "advancedBy": "\(advanceBy)s",
                "clockTime": "\(testClock.currentTime)",
            ])
            Issue.record(
                "Overlay not visible after advancing clock by \(advanceBy)s\n\n\(dump)",
                sourceLocation: sourceLocation,
            )
        }
    }

    // MARK: - Diagnostic Dump

    /// Produces a diagnostic snapshot for debugging test failures.
    /// Includes scheduler state, overlay state, DB counts, and recent flight recorder entries.
    func diagnosticDump(context: [String: String] = [:]) -> String {
        let stateSnapshot: [String: String] = [
            "scheduledAlerts": "\(eventScheduler.scheduledAlerts.count)",
            "alertDetails": eventScheduler.scheduledAlerts.prefix(TestConstants.diagnosticAlertLimit)
                .map { "\($0.event.id)@\($0.triggerDate)" }
                .joined(separator: "; "),
            "overlayVisible": "\(overlayManager.isOverlayVisible)",
            "activeEvent": overlayManager.activeEvent.map { PrivacyUtils.redactedEventId($0.id) } ?? "<none>",
            "clockTime": "\(testClock.currentTime)",
        ]

        return DiagnosticsBookExporter.export(
            stateSnapshot: stateSnapshot,
            testContext: context,
        )
    }

    // MARK: - Teardown

    func tearDown() {
        // Cancel monitoring FIRST — this marks the task as cancelled.
        // Any pending TestClock continuations will throw CancellationError
        // when they resume. The continuations leak (TestClock holds them),
        // but they're cleaned up when the TestClock is deallocated (env = nil).
        eventScheduler.stopScheduling()
        overlayManager.hideOverlay()
    }
}

// MARK: - Test Constants

private enum TestConstants {
    static let defaultAlertMinutes = 5
    static let overlayShowMinutesBefore = 2
    static let diagnosticAlertLimit = 10
    static let fetchLimit = 100
    static let defaultUpcomingLimit = 50
    static let defaultStartedLimit = 10
    static let secondsPerMinute: TimeInterval = 60
    static let oneHourSeconds: TimeInterval = 3600
    static let twoHoursAgoSeconds: TimeInterval = -7200
    static let oneHourAgoSeconds: TimeInterval = -3600
    static let oneDaySeconds: TimeInterval = 86_400
    static let hoursPerDay: TimeInterval = 24
    static let e2ePollIntervalNanoseconds: UInt64 = 100_000_000
}

// MARK: - E2E Errors

enum E2EError: LocalizedError {
    case databaseInitFailed(String)

    var errorDescription: String? {
        switch self {
        case let .databaseInitFailed(message):
            "E2E database initialization failed: \(message)"
        }
    }
}

// MARK: - E2E Test Event Builders

enum E2EEventBuilder {
    /// Creates a future event at a specific offset from now
    static func futureEvent(
        id: String = "e2e-\(UUID().uuidString)",
        title: String = "E2E Test Meeting",
        minutesFromNow: Int = 10,
        durationMinutes: Int = 60,
        organizer: String? = "organizer@example.com",
        calendarId: String = "e2e-calendar",
        links: [URL] = [],
        provider: Provider? = nil,
        isAllDay: Bool = false,
    ) -> Event {
        let start = Date().addingTimeInterval(TimeInterval(minutesFromNow) * TestConstants.secondsPerMinute)
        let end = start.addingTimeInterval(TimeInterval(durationMinutes) * TestConstants.secondsPerMinute)

        return Event(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            organizer: organizer,
            isAllDay: isAllDay,
            calendarId: calendarId,
            links: links,
            provider: provider,
            createdAt: Date(),
            updatedAt: Date(),
        )
    }

    /// Creates an event that has already started
    static func startedEvent(
        id: String = "e2e-started-\(UUID().uuidString)",
        title: String = "Started E2E Meeting",
        minutesAgo: Int = 5,
        durationMinutes: Int = 60,
        calendarId: String = "e2e-calendar",
    ) -> Event {
        let start = Date().addingTimeInterval(TimeInterval(-minutesAgo) * TestConstants.secondsPerMinute)
        let end = start.addingTimeInterval(TimeInterval(durationMinutes) * TestConstants.secondsPerMinute)

        return Event(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            calendarId: calendarId,
            createdAt: Date(),
            updatedAt: Date(),
        )
    }

    /// Creates an event that ended in the past
    static func pastEvent(
        id: String = "e2e-past-\(UUID().uuidString)",
        title: String = "Past E2E Meeting",
        calendarId: String = "e2e-calendar",
    ) -> Event {
        Event(
            id: id,
            title: title,
            startDate: Date().addingTimeInterval(TestConstants.twoHoursAgoSeconds),
            endDate: Date().addingTimeInterval(TestConstants.oneHourAgoSeconds),
            calendarId: calendarId,
            createdAt: Date(),
            updatedAt: Date(),
        )
    }

    /// Creates an all-day event
    static func allDayEvent(
        id: String = "e2e-allday-\(UUID().uuidString)",
        title: String = "All Day E2E Event",
        calendarId: String = "e2e-calendar",
    ) -> Event {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = start.addingTimeInterval(TestConstants.hoursPerDay * TestConstants.oneHourSeconds)

        return Event(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: true,
            calendarId: calendarId,
            createdAt: Date(),
            updatedAt: Date(),
        )
    }

    /// Creates an event with a meeting link
    static func onlineMeeting(
        id: String = "e2e-online-\(UUID().uuidString)",
        title: String = "Online E2E Meeting",
        minutesFromNow: Int = 10,
        provider: Provider = .meet,
        calendarId: String = "e2e-calendar",
    ) -> Event {
        // swiftlint:disable force_unwrapping
        let link = switch provider {
        case .meet:
            URL(string: "https://meet.google.com/e2e-test-room")!
        case .zoom:
            URL(string: "https://zoom.us/j/999888777")!
        case .teams:
            URL(string: "https://teams.microsoft.com/l/meetup-join/e2e-test")!
        case .webex:
            URL(string: "https://example.webex.com/meet/e2e-test")!
        case .discord:
            URL(string: "https://discord.gg/e2e-test")!
        case .generic:
            URL(string: "https://example.com/meeting/e2e-test")!
        }
        // swiftlint:enable force_unwrapping

        return futureEvent(
            id: id,
            title: title,
            minutesFromNow: minutesFromNow,
            calendarId: calendarId,
            links: [link],
            provider: provider,
        )
    }

    /// Creates a batch of events spaced apart
    static func eventBatch(
        count: Int,
        startingMinutesFromNow: Int = 10,
        spacingMinutes: Int = 15,
        calendarId: String = "e2e-calendar",
    ) -> [Event] {
        (0 ..< count).map { index in
            futureEvent(
                id: "e2e-batch-\(index)",
                title: "Batch Meeting \(index + 1)",
                minutesFromNow: startingMinutesFromNow + (index * spacingMinutes),
                calendarId: calendarId,
            )
        }
    }
}

// MARK: - E2E Assertion Helpers

/// Waits for an async condition with a descriptive failure message.
@MainActor
func e2eWait(
    timeout: TimeInterval = 5.0,
    description: String,
    condition: @escaping @MainActor @Sendable () -> Bool,
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else {
            Issue.record("E2E wait timed out: \(description)")
            return
        }
        // E2E polling utility (equivalent to TestUtilities.waitForAsync)
        // swiftlint:disable:next no_raw_task_sleep_in_tests
        try await Task.sleep(nanoseconds: TestConstants.e2ePollIntervalNanoseconds)
    }
}
