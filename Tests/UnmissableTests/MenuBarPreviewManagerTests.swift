import Foundation
import Testing
@testable import Unmissable

@MainActor
struct MenuBarPreviewManagerTests {
    private var prefs: PreferencesManager
    private var manager: MenuBarPreviewManager

    init() {
        prefs = TestUtilities.createTestPreferencesManager()
        manager = MenuBarPreviewManager(preferencesManager: prefs)
    }

    // MARK: - Icon Mode

    @Test
    func iconMode_showsIconAndNoText() {
        prefs.setMenuBarDisplayMode(.icon)
        manager.updateEvents([
            TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600)),
        ])

        #expect(manager.shouldShowIcon, "Icon mode should show the icon")
        #expect(manager.menuBarText == nil, "Icon mode should have no text")
    }

    // MARK: - Timer Mode

    @Test
    func timerMode_withFutureEvent_showsTimerText() throws {
        prefs.setMenuBarDisplayMode(.timer)
        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(1800), // 30 minutes
        )
        manager.updateEvents([futureEvent])

        #expect(!manager.shouldShowIcon, "Timer mode with events should hide icon")
        let text = try #require(manager.menuBarText, "Timer mode with events should show text")
        let hasTimeUnit = text.contains("min") || text.contains("h") || text.contains("Starting")
        #expect(hasTimeUnit, "Timer text should contain a time unit, got: \(text)")
    }

    @Test
    func timerMode_withNoEvents_fallsBackToIcon() {
        prefs.setMenuBarDisplayMode(.timer)
        manager.updateEvents([])

        #expect(manager.shouldShowIcon, "Timer mode without events should show icon")
        #expect(manager.menuBarText == nil, "Timer mode without events should have no text")
    }

    @Test
    func timerMode_withPastEventOnly_fallsBackToIcon() {
        prefs.setMenuBarDisplayMode(.timer)
        let pastEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-3600),
        )
        manager.updateEvents([pastEvent])

        #expect(manager.shouldShowIcon, "Timer mode with only past events should show icon")
        #expect(manager.menuBarText == nil)
    }

    @Test
    func timerMode_withInProgressEvent_showsStarting() {
        prefs.setMenuBarDisplayMode(.timer)
        let inProgress = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(-60), // started 1 min ago
            endDate: Date().addingTimeInterval(3540), // ends in ~59 min
        )
        manager.updateEvents([inProgress])

        #expect(!manager.shouldShowIcon)
        #expect(manager.menuBarText == "Starting", "In-progress event should show 'Starting'")
    }

    // MARK: - Name+Timer Mode

    @Test
    func nameTimerMode_showsNameAndTime() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let event = TestUtilities.createTestEvent(
            title: "Team Sync",
            startDate: Date().addingTimeInterval(1800),
        )
        manager.updateEvents([event])

        #expect(!manager.shouldShowIcon)
        let text = try #require(manager.menuBarText, "Name+Timer should produce text")
        #expect(text.hasPrefix("Team Sync"), "Name+Timer should start with meeting name, got: \(text)")
        let hasTime = text.contains("min") || text.contains("h")
        #expect(hasTime, "Name+Timer should contain time, got: \(text)")
    }

    @Test
    func nameTimerMode_truncatesLongNames() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let event = TestUtilities.createTestEvent(
            title: "Very Important Strategic Planning Meeting",
            startDate: Date().addingTimeInterval(1800),
        )
        manager.updateEvents([event])

        let text = try #require(manager.menuBarText, "Should produce text for truncation test")
        // Name should be truncated to 9 chars + "..."
        #expect(text.hasPrefix("Very Impo..."), "Long name should be truncated, got: \(text)")
    }

    @Test
    func nameTimerMode_shortNameNotTruncated() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let event = TestUtilities.createTestEvent(
            title: "Short Name",
            startDate: Date().addingTimeInterval(1800),
        )
        manager.updateEvents([event])

        let text = try #require(manager.menuBarText, "Should produce text for short name test")
        #expect(text.hasPrefix("Short Name"), "Short names (<= 12 chars) should not be truncated, got: \(text)")
    }

    // MARK: - Event Priority

    @Test
    func inProgressEventTakesPriorityOverFutureEvent() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let inProgress = TestUtilities.createTestEvent(
            title: "Current Meeting",
            startDate: Date().addingTimeInterval(-300),
            endDate: Date().addingTimeInterval(3300),
        )
        let future = TestUtilities.createTestEvent(
            title: "Future Meeting",
            startDate: Date().addingTimeInterval(1800),
        )
        manager.updateEvents([future, inProgress])

        let text = try #require(manager.menuBarText, "Should produce text for priority test")
        #expect(text.hasPrefix("Current"), "In-progress meeting should take priority, got: \(text)")
    }

    @Test
    func nearestFutureEventIsSelected() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let far = TestUtilities.createTestEvent(
            title: "Far Meeting",
            startDate: Date().addingTimeInterval(7200),
        )
        let near = TestUtilities.createTestEvent(
            title: "Near Meetin",
            startDate: Date().addingTimeInterval(600),
        )
        manager.updateEvents([far, near])

        let text = try #require(manager.menuBarText, "Should produce text for nearest future test")
        #expect(text.hasPrefix("Near Meetin"), "Nearest future meeting should be selected, got: \(text)")
    }

    // MARK: - Format Time Left Boundaries

    @Test
    func timerMode_lessThanOneMinute() {
        prefs.setMenuBarDisplayMode(.timer)
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(30),
        )
        manager.updateEvents([event])

        #expect(manager.menuBarText == "< 1 min")
    }

    @Test
    func timerMode_overOneHour() throws {
        prefs.setMenuBarDisplayMode(.timer)
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(3660), // 61 minutes to avoid rounding below 60
        )
        manager.updateEvents([event])

        let text = try #require(manager.menuBarText, "Should produce text for hour format test")
        #expect(text.contains("h"), "Over 1 hour should use hour format, got: \(text)")
    }

    @Test
    func timerMode_overOneDay() throws {
        prefs.setMenuBarDisplayMode(.timer)
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(100_000),
        )
        manager.updateEvents([event])

        let text = try #require(manager.menuBarText, "Should produce text for day format test")
        #expect(text.contains("d"), "Over 1 day should use day format, got: \(text)")
    }

    // MARK: - Mode Switching

    @Test
    func switchingFromTimerToIconClearsText() async throws {
        prefs.setMenuBarDisplayMode(.timer)
        manager.updateEvents([
            TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(1800)),
        ])
        let preSwitch = try #require(manager.menuBarText, "Timer mode should produce text before mode switch")
        #expect(!preSwitch.isEmpty, "Timer text should be non-empty")

        prefs.setMenuBarDisplayMode(.icon)

        // Wait for the Combine sink to fire and state to update
        try await TestUtilities.waitForAsync(timeout: 10.0) { @MainActor @Sendable in
            manager.shouldShowIcon
        }

        #expect(manager.shouldShowIcon)
        #expect(manager.menuBarText == nil, "Switching to icon mode should clear text")
    }
}
