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

    func testTimerMode_withFutureEvent_showsTimerText() {
        prefs.setMenuBarDisplayMode(.timer)
        let futureEvent = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(1800) // 30 minutes
        )
        manager.updateEvents([futureEvent])

        XCTAssertFalse(manager.shouldShowIcon, "Timer mode with events should hide icon")
        XCTAssertNotNil(manager.menuBarText, "Timer mode with events should show text")
        let text = manager.menuBarText ?? ""
        XCTAssertTrue(
            text.contains("min") || text.contains("h") || text.contains("Starting"),
            "Timer text should contain a time unit, got: \(text)"
        )
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

    func testNameTimerMode_showsNameAndTime() {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let event = TestUtilities.createTestEvent(
            title: "Team Sync",
            startDate: Date().addingTimeInterval(1800)
        )
        manager.updateEvents([event])

        XCTAssertFalse(manager.shouldShowIcon)
        let text = manager.menuBarText ?? ""
        XCTAssertTrue(
            text.contains("Team Sync"),
            "Name+Timer should contain meeting name, got: \(text)"
        )
        XCTAssertTrue(
            text.contains("min") || text.contains("h"),
            "Name+Timer should contain time, got: \(text)"
        )
    }

    func testNameTimerMode_truncatesLongNames() {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let event = TestUtilities.createTestEvent(
            title: "Very Important Strategic Planning Meeting",
            startDate: Date().addingTimeInterval(1800)
        )
        manager.updateEvents([event])

        let text = manager.menuBarText ?? ""
        // Name should be truncated to 9 chars + "..."
        XCTAssertTrue(
            text.hasPrefix("Very Impo..."),
            "Long name should be truncated, got: \(text)"
        )
    }

    func testNameTimerMode_shortNameNotTruncated() {
        prefs.setMenuBarDisplayMode(.nameTimer)
        let event = TestUtilities.createTestEvent(
            title: "Short Name",
            startDate: Date().addingTimeInterval(1800)
        )
        manager.updateEvents([event])

        let text = manager.menuBarText ?? ""
        XCTAssertTrue(
            text.hasPrefix("Short Name"),
            "Short names (<= 12 chars) should not be truncated, got: \(text)"
        )
    }

    // MARK: - Event Priority

    func testInProgressEventTakesPriorityOverFutureEvent() {
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

        let text = manager.menuBarText ?? ""
        XCTAssertTrue(
            text.contains("Current"),
            "In-progress meeting should take priority, got: \(text)"
        )
    }

    func testNearestFutureEventIsSelected() {
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

        let text = manager.menuBarText ?? ""
        XCTAssertTrue(
            text.contains("Near Meetin"),
            "Nearest future meeting should be selected, got: \(text)"
        )
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

    func testTimerMode_overOneHour() {
        prefs.setMenuBarDisplayMode(.timer)
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(3660) // 61 minutes to avoid rounding below 60
        )
        manager.updateEvents([event])

        let text = manager.menuBarText ?? ""
        XCTAssertTrue(text.contains("h"), "Over 1 hour should use hour format, got: \(text)")
    }

    func testTimerMode_overOneDay() {
        prefs.setMenuBarDisplayMode(.timer)
        let event = TestUtilities.createTestEvent(
            startDate: Date().addingTimeInterval(100_000)
        )
        manager.updateEvents([event])

        let text = manager.menuBarText ?? ""
        XCTAssertTrue(text.contains("d"), "Over 1 day should use day format, got: \(text)")
    }

    // MARK: - Mode Switching

    func testSwitchingFromTimerToIconClearsText() {
        prefs.setMenuBarDisplayMode(.timer)
        manager.updateEvents([
            TestUtilities.createTestEvent(startDate: Date().addingTimeInterval(1800)),
        ])
        XCTAssertNotNil(manager.menuBarText)

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
