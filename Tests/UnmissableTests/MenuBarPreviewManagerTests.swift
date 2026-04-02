@testable import Unmissable
import XCTest

@MainActor
final class MenuBarPreviewManagerTests: XCTestCase {
    private var prefs: PreferencesManager!
    private var manager: MenuBarPreviewManager!

    override func setUp() async throws {
        try await super.setUp()
        prefs = TestUtilities.createTestPreferencesManager()
        manager = MenuBarPreviewManager(preferencesManager: prefs)
    }

    override func tearDown() async throws {
        manager = nil
        prefs = nil
        try await super.tearDown()
    }

    // MARK: - Icon Mode

    func testIconMode_showsIconAndNoText() {
        prefs.setMenuBarDisplayMode(.icon)
        manager.updateEvents([
            TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(600)),
        ])

        XCTAssertTrue(manager.shouldShowIcon, "Icon mode should show the icon")
        XCTAssertNil(manager.menuBarText, "Icon mode should have no text")
    }

    // MARK: - Timer Mode

    func testTimerMode_withFutureEvent_showsTimerText() throws {
        prefs.setMenuBarDisplayMode(.timer)
        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(1800) // 30 minutes
        )
        manager.updateEvents([futureEvent])

        XCTAssertFalse(manager.shouldShowIcon, "Timer mode with events should hide icon")
        let text = try XCTUnwrap(manager.menuBarText, "Timer mode with events should show text")
        let hasTimeUnit = text.contains("min") || text.contains("h") || text.contains("Starting")
        XCTAssert(hasTimeUnit, "Timer text should contain a time unit, got: \(text)")
    }

    func testTimerMode_withNoEvents_fallsBackToIcon() {
        prefs.setMenuBarDisplayMode(.timer)
        manager.updateEvents([])

        XCTAssertTrue(manager.shouldShowIcon, "Timer mode without events should show icon")
        XCTAssertNil(manager.menuBarText, "Timer mode without events should have no text")
    }

    func testTimerMode_withPastEventOnly_fallsBackToIcon() {
        prefs.setMenuBarDisplayMode(.timer)
        let pastEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-3600)
        )
        manager.updateEvents([pastEvent])

        XCTAssertTrue(manager.shouldShowIcon, "Timer mode with only past events should show icon")
        XCTAssertNil(manager.menuBarText)
    }

    func testTimerMode_withInProgressEvent_showsStarting() {
        prefs.setMenuBarDisplayMode(.timer)
        let inProgress = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(-60), // started 1 min ago
            endDate: Date().addingTimeInterval(3540) // ends in ~59 min
        )
        manager.updateEvents([inProgress])

        XCTAssertFalse(manager.shouldShowIcon)
        XCTAssertEqual(manager.menuBarText, "Starting", "In-progress event should show 'Starting'")
    }

    // MARK: - Name+Timer Mode

    func testNameTimerMode_showsNameAndTime() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let event = TestUtilities.createTestEvent(
            title: "Team Sync",
            startDate: Date().addingTimeInterval(1800)
        )
        manager.updateEvents([event])

        XCTAssertFalse(manager.shouldShowIcon)
        let text = try XCTUnwrap(manager.menuBarText, "Name+Timer should produce text")
        XCTAssert(text.hasPrefix("Team Sync"), "Name+Timer should start with meeting name, got: \(text)")
        let hasTime = text.contains("min") || text.contains("h")
        XCTAssert(hasTime, "Name+Timer should contain time, got: \(text)")
    }

    func testNameTimerMode_truncatesLongNames() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let event = TestUtilities.createTestEvent(
            title: "Very Important Strategic Planning Meeting",
            startDate: Date().addingTimeInterval(1800)
        )
        manager.updateEvents([event])

        let text = try XCTUnwrap(manager.menuBarText, "Should produce text for truncation test")
        // Name should be truncated to 9 chars + "..."
        XCTAssert(text.hasPrefix("Very Impo..."), "Long name should be truncated, got: \(text)")
    }

    func testNameTimerMode_shortNameNotTruncated() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let event = TestUtilities.createTestEvent(
            title: "Short Name",
            startDate: Date().addingTimeInterval(1800)
        )
        manager.updateEvents([event])

        let text = try XCTUnwrap(manager.menuBarText, "Should produce text for short name test")
        XCTAssert(text.hasPrefix("Short Name"), "Short names (<= 12 chars) should not be truncated, got: \(text)")
    }

    // MARK: - Event Priority

    func testInProgressEventTakesPriorityOverFutureEvent() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let inProgress = TestUtilities.createTestEvent(
            title: "Current Meeting",
            startDate: Date().addingTimeInterval(-300),
            endDate: Date().addingTimeInterval(3300)
        )
        let future = TestUtilities.createTestEvent(
            title: "Future Meeting",
            startDate: Date().addingTimeInterval(1800)
        )
        manager.updateEvents([future, inProgress])

        let text = try XCTUnwrap(manager.menuBarText, "Should produce text for priority test")
        XCTAssert(text.hasPrefix("Current"), "In-progress meeting should take priority, got: \(text)")
    }

    func testNearestFutureEventIsSelected() throws {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let far = TestUtilities.createTestEvent(
            title: "Far Meeting",
            startDate: Date().addingTimeInterval(7200)
        )
        let near = TestUtilities.createTestEvent(
            title: "Near Meetin",
            startDate: Date().addingTimeInterval(600)
        )
        manager.updateEvents([far, near])

        let text = try XCTUnwrap(manager.menuBarText, "Should produce text for nearest future test")
        XCTAssert(text.hasPrefix("Near Meetin"), "Nearest future meeting should be selected, got: \(text)")
    }

    // MARK: - Format Time Left Boundaries

    func testTimerMode_lessThanOneMinute() {
        prefs.setMenuBarDisplayMode(.timer)
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(30)
        )
        manager.updateEvents([event])

        XCTAssertEqual(manager.menuBarText, "< 1 min")
    }

    func testTimerMode_overOneHour() throws {
        prefs.setMenuBarDisplayMode(.timer)
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(3660) // 61 minutes to avoid rounding below 60
        )
        manager.updateEvents([event])

        let text = try XCTUnwrap(manager.menuBarText, "Should produce text for hour format test")
        XCTAssert(text.contains("h"), "Over 1 hour should use hour format, got: \(text)")
    }

    func testTimerMode_overOneDay() throws {
        prefs.setMenuBarDisplayMode(.timer)
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(100_000)
        )
        manager.updateEvents([event])

        let text = try XCTUnwrap(manager.menuBarText, "Should produce text for day format test")
        XCTAssert(text.contains("d"), "Over 1 day should use day format, got: \(text)")
    }

    // MARK: - Mode Switching

    func testSwitchingFromTimerToIconClearsText() throws {
        prefs.setMenuBarDisplayMode(.timer)
        manager.updateEvents([
            TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(1800)),
        ])
        let preSwitch = try XCTUnwrap(manager.menuBarText, "Timer mode should produce text before mode switch")
        XCTAssertFalse(preSwitch.isEmpty, "Timer text should be non-empty")

        prefs.setMenuBarDisplayMode(.icon)

        // Give Combine sink time to fire
        let expectation = XCTestExpectation(description: "Mode switch propagated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(manager.shouldShowIcon)
        XCTAssertNil(manager.menuBarText, "Switching to icon mode should clear text")
    }
}
