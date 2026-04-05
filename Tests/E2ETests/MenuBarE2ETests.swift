import Foundation
import Testing
@testable import Unmissable

/// E2E tests for the menu bar entry point: the state pipeline that drives
/// `MenuBarView` and `MenuBarLabelView`. Verifies that CalendarService state,
/// MenuBarPreviewManager output, and EventGrouping results are consistent
/// across the full data flow.
///
/// These tests complement the existing E2E suite (DB → scheduler → overlay)
/// by covering the other half of the app: the menu bar popover that users
/// interact with on every launch.
@MainActor
struct MenuBarE2ETests {
    private let env: TestMenuBarEnvironment

    init() {
        env = TestMenuBarEnvironment()
    }

    // MARK: - Menu Bar Preview State Pipeline

    @Test
    func menuBarPreview_iconMode_showsIconRegardlessOfEvents() {
        env.preferencesManager.setMenuBarDisplayMode(.icon)
        let event = createFutureEvent(minutesFromNow: 10)
        env.menuBarPreviewManager.updateEvents([event])

        #expect(env.menuBarPreviewManager.shouldShowIcon)
        #expect(env.menuBarPreviewManager.menuBarText == nil)
    }

    @Test
    func menuBarPreview_timerMode_withFutureEvent_showsCountdown() throws {
        env.preferencesManager.setMenuBarDisplayMode(.timer)
        let event = createFutureEvent(minutesFromNow: 30)
        env.menuBarPreviewManager.updateEvents([event])

        #expect(!env.menuBarPreviewManager.shouldShowIcon)
        let text = try #require(env.menuBarPreviewManager.menuBarText)
        #expect(text.contains("min"), "Expected timer text with minutes, got: \(text)")
    }

    @Test
    func menuBarPreview_timerMode_noEvents_fallsBackToIcon() {
        env.preferencesManager.setMenuBarDisplayMode(.timer)
        env.menuBarPreviewManager.updateEvents([])

        #expect(env.menuBarPreviewManager.shouldShowIcon)
        #expect(env.menuBarPreviewManager.menuBarText == nil)
    }

    @Test
    func menuBarPreview_nameTimerMode_showsNameAndCountdown() throws {
        env.preferencesManager.setMenuBarDisplayMode(.nameTimer)
        let event = createFutureEvent(title: "Standup", minutesFromNow: 15)
        env.menuBarPreviewManager.updateEvents([event])

        #expect(!env.menuBarPreviewManager.shouldShowIcon)
        let text = try #require(env.menuBarPreviewManager.menuBarText)
        #expect(text.hasPrefix("Standup"), "Expected name prefix, got: \(text)")
        #expect(text.contains("min"), "Expected time suffix, got: \(text)")
    }

    @Test
    func menuBarPreview_nameTimerMode_inProgressEvent_showsStarting() throws {
        env.preferencesManager.setMenuBarDisplayMode(.nameTimer)
        let inProgress = createEvent(
            title: "Active Call",
            startDate: Date().addingTimeInterval(-60),
            endDate: Date().addingTimeInterval(3540),
        )
        env.menuBarPreviewManager.updateEvents([inProgress])

        let text = try #require(env.menuBarPreviewManager.menuBarText)
        #expect(text.contains("Starting"), "In-progress event should show 'Starting', got: \(text)")
    }

    @Test
    func menuBarPreview_nearestEventSelected_overFarEvent() throws {
        env.preferencesManager.setMenuBarDisplayMode(.nameTimer)
        let farEvent = createFutureEvent(title: "Far Meeting", minutesFromNow: 120)
        let nearEvent = createFutureEvent(title: "Near Meet", minutesFromNow: 5)
        env.menuBarPreviewManager.updateEvents([farEvent, nearEvent])

        let text = try #require(env.menuBarPreviewManager.menuBarText)
        #expect(text.hasPrefix("Near Meet"), "Nearest event should be selected, got: \(text)")
    }

    @Test
    func menuBarPreview_allDayEvents_excludedFromTimer() {
        env.preferencesManager.setMenuBarDisplayMode(.timer)
        let allDay = createAllDayEvent()
        env.menuBarPreviewManager.updateEvents([allDay])

        #expect(
            env.menuBarPreviewManager.shouldShowIcon,
            "All-day events should not appear in timer — they aren't joinable meetings",
        )
        #expect(env.menuBarPreviewManager.menuBarText == nil)
    }

    // MARK: - Event Grouping Pipeline

    @Test
    func eventGrouping_todayEvents_groupedUnderToday() {
        let todayEvent = createFutureEvent(title: "Today Meeting", minutesFromNow: 30)
        let groups = EventGrouping.groupByDate(
            [todayEvent],
            includeAllDay: false,
        )

        #expect(groups.count == 1)
        #expect(groups.first?.title == "Today")
        #expect(groups.first?.events.count == 1)
        #expect(groups.first?.events.first?.title == "Today Meeting")
    }

    @Test
    func eventGrouping_startedEvents_groupedFirst() {
        let startedEvent = createEvent(
            title: "In Progress",
            startDate: Date().addingTimeInterval(-300),
            endDate: Date().addingTimeInterval(3300),
        )
        let futureEvent = createFutureEvent(title: "Upcoming", minutesFromNow: 60)

        let groups = EventGrouping.groupByDate(
            [futureEvent],
            startedEvents: [startedEvent],
            includeAllDay: false,
        )

        #expect(groups.count >= 2)
        #expect(groups[0].title == "Started")
        #expect(groups[0].events.first?.title == "In Progress")
        #expect(groups[1].title == "Today")
        #expect(groups[1].events.first?.title == "Upcoming")
    }

    @Test
    func eventGrouping_allDayExcluded_whenPreferenceOff() {
        let allDay = createAllDayEvent()
        let regular = createFutureEvent(minutesFromNow: 30)

        // The production pipeline pre-filters via upcomingEvents before grouping
        let filtered = EventGrouping.upcomingEvents(
            from: [allDay, regular],
            includeAllDay: false,
        )
        let groups = EventGrouping.groupByDate(
            filtered,
            includeAllDay: false,
        )

        let allEvents = groups.flatMap(\.events)
        let hasAllDay = allEvents.contains(where: \.isAllDay)
        #expect(!hasAllDay, "All-day events should be excluded")
        #expect(allEvents.count == 1)
    }

    @Test
    func eventGrouping_allDayIncluded_whenPreferenceOn() {
        let allDay = createAllDayEvent()
        let regular = createFutureEvent(minutesFromNow: 30)

        let filtered = EventGrouping.upcomingEvents(
            from: [allDay, regular],
            includeAllDay: true,
        )
        let groups = EventGrouping.groupByDate(
            filtered,
            includeAllDay: true,
        )

        let allEvents = groups.flatMap(\.events)
        let hasAllDay = allEvents.contains(where: \.isAllDay)
        #expect(hasAllDay, "All-day events should be included")
        #expect(allEvents.count == 2)
    }

    @Test
    func eventGrouping_emptyEvents_producesNoGroups() {
        let groups = EventGrouping.groupByDate([], includeAllDay: false)
        #expect(groups.isEmpty)
    }

    // MARK: - Calendar Service State → View Data

    @Test
    func calendarService_disconnected_showsDisconnectedUI() {
        env.calendarService.isConnected = false
        env.calendarService.events = []
        env.calendarService.authError = nil

        #expect(!env.calendarService.isConnected)
        #expect(env.calendarService.events.isEmpty)
    }

    @Test
    func calendarService_disconnectedWithAuthError_exposesError() {
        env.calendarService.isConnected = false
        env.calendarService.authError = "Missing OAuth configuration"

        #expect(env.calendarService.authError == "Missing OAuth configuration")
        #expect(!env.calendarService.isConnected)
    }

    @Test
    func calendarService_connected_withEvents_exposesEventData() {
        let event = createFutureEvent(title: "Team Sync", minutesFromNow: 15)
        env.calendarService.isConnected = true
        env.calendarService.events = [event]
        env.calendarService.syncStatus = .idle

        #expect(env.calendarService.isConnected)
        #expect(env.calendarService.events.count == 1)
        #expect(env.calendarService.events.first?.title == "Team Sync")
    }

    @Test
    func calendarService_syncingState_reflectedInStatus() {
        env.calendarService.isConnected = true
        env.calendarService.syncStatus = .syncing

        if case .syncing = env.calendarService.syncStatus {
            // pass
        } else {
            Issue.record("Expected syncing status")
        }
    }

    @Test
    func calendarService_syncErrorState_reflectedInStatus() {
        env.calendarService.isConnected = true
        env.calendarService.syncStatus = .error("Network timeout")

        if case let .error(message) = env.calendarService.syncStatus {
            #expect(message == "Network timeout")
        } else {
            Issue.record("Expected error status")
        }
    }

    // MARK: - AppState → View Data

    @Test
    func appState_databaseError_availableForView() {
        env.appState.databaseError = "Failed to initialize database"
        #expect(env.appState.databaseError == "Failed to initialize database")
    }

    @Test
    func appState_noDatabaseError_isNil() {
        #expect(env.appState.databaseError == nil)
    }

    // MARK: - Full Pipeline: Events → Preview + Grouping

    @Test
    func fullPipeline_eventsFlowToPreviewAndGrouping() throws {
        env.preferencesManager.setMenuBarDisplayMode(.timer)

        let event1 = createFutureEvent(title: "First Meeting", minutesFromNow: 10)
        let event2 = createFutureEvent(title: "Second Meeting", minutesFromNow: 60)

        env.calendarService.isConnected = true
        env.calendarService.events = [event1, event2]

        // Preview should reflect the nearest event
        env.menuBarPreviewManager.updateEvents([event1, event2])
        let timerText = try #require(env.menuBarPreviewManager.menuBarText)
        #expect(timerText.contains("min"), "Timer should show minutes for 10m event, got: \(timerText)")

        // Grouping should produce "Today" group with both events
        let groups = EventGrouping.groupByDate(
            [event1, event2],
            includeAllDay: false,
        )
        #expect(groups.count == 1)
        #expect(groups.first?.title == "Today")
        #expect(groups.first?.events.count == 2)
    }

    @Test
    func fullPipeline_modeSwitchFromTimerToIcon_clearsText() async throws {
        env.preferencesManager.setMenuBarDisplayMode(.timer)
        let event = createFutureEvent(minutesFromNow: 15)
        env.menuBarPreviewManager.updateEvents([event])

        let preSwitch = try #require(env.menuBarPreviewManager.menuBarText)
        #expect(!preSwitch.isEmpty)

        // Switch to icon mode
        env.preferencesManager.setMenuBarDisplayMode(.icon)

        // Poll until the observation fires and menuBarText clears, instead of
        // sleeping for a fixed wall-clock duration.
        let deadline = Date().addingTimeInterval(2.0)
        while env.menuBarPreviewManager.menuBarText != nil, Date() < deadline {
            // swiftlint:disable:next no_raw_task_sleep_in_tests
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(env.menuBarPreviewManager.shouldShowIcon)
        #expect(env.menuBarPreviewManager.menuBarText == nil)
    }

    // MARK: - Event Helpers

    private static let secondsPerMinute: TimeInterval = 60
    private static let oneHour: TimeInterval = 3600

    private func createFutureEvent(
        id: String = "e2e-menubar-\(UUID().uuidString)",
        title: String = "Test Meeting",
        minutesFromNow: Int = 15,
        durationMinutes: Int = 60,
    ) -> Event {
        let start = Date().addingTimeInterval(TimeInterval(minutesFromNow) * Self.secondsPerMinute)
        let end = start.addingTimeInterval(TimeInterval(durationMinutes) * Self.secondsPerMinute)
        return Event(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            calendarId: "e2e-menubar-cal",
            createdAt: Date(),
            updatedAt: Date(),
        )
    }

    private func createEvent(
        id: String = "e2e-menubar-\(UUID().uuidString)",
        title: String = "Test Meeting",
        startDate: Date,
        endDate: Date,
    ) -> Event {
        Event(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            calendarId: "e2e-menubar-cal",
            createdAt: Date(),
            updatedAt: Date(),
        )
    }

    private func createAllDayEvent(
        id: String = "e2e-allday-\(UUID().uuidString)",
        title: String = "All Day Event",
    ) -> Event {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = start.addingTimeInterval(24 * Self.oneHour)
        return Event(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: true,
            calendarId: "e2e-menubar-cal",
            createdAt: Date(),
            updatedAt: Date(),
        )
    }
}
