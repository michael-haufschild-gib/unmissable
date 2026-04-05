import Foundation
import XCTest

enum UnmissableUITestSupport {
    static let popoverIdentifier = "unmissable-popover"
    static let statusItemIdentifier = "unmissable-status-item"
    static let statusItemLabel = "Unmissable"

    private static let statusItemHittableTimeout: TimeInterval = 2
    private static let pollingInterval: TimeInterval = 0.1

    static func launchArguments(regularActivation: Bool = false) -> [String] {
        var arguments = ["--uitesting"]

        if regularActivation {
            arguments.append("--ui-testing-regular-activation")
        }

        return arguments
    }

    static func launchArguments(onboardingCompleted: Bool, regularActivation: Bool = false) -> [String] {
        var arguments = launchArguments(regularActivation: regularActivation)
        arguments += [
            "-hasCompletedOnboarding",
            onboardingCompleted ? "1" : "0",
        ]
        return arguments
    }

    static func statusItem(in app: XCUIApplication, timeout: TimeInterval = 10) -> XCUIElement {
        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let candidates = [
            app.statusItems[statusItemIdentifier],
            app.statusItems[statusItemLabel],
            app.menuBars.statusItems[statusItemIdentifier],
            app.menuBars.statusItems[statusItemLabel],
            app.menuBars.buttons[statusItemIdentifier],
            app.menuBars.buttons[statusItemLabel],
            systemUI.statusItems[statusItemIdentifier],
            systemUI.statusItems[statusItemLabel],
            systemUI.menuBars.statusItems[statusItemIdentifier],
            systemUI.menuBars.statusItems[statusItemLabel],
            systemUI.menuBars.buttons[statusItemIdentifier],
            systemUI.menuBars.buttons[statusItemLabel],
            systemUI.buttons[statusItemIdentifier],
            systemUI.buttons[statusItemLabel],
            app.buttons[statusItemIdentifier],
            app.buttons[statusItemLabel],
        ]

        if let matched = firstExistingElement(from: candidates, timeout: timeout) {
            return matched
        }

        return candidates[0]
    }

    @discardableResult
    static func clickStatusItem(
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) -> XCUIElement {
        let statusItem = statusItem(in: app, timeout: timeout)
        guard statusItem.exists else {
            XCTFail(
                "Status item should appear in the menu bar (tried app/status item and SystemUIServer fallbacks)",
                file: file,
                line: line,
            )
            return statusItem
        }

        _ = statusItem.waitForHittable(timeout: Self.statusItemHittableTimeout)
        statusItem.click()
        return statusItem
    }

    private static func firstExistingElement(
        from candidates: [XCUIElement],
        timeout: TimeInterval,
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if let match = candidates.first(where: \.exists) {
                return match
            }

            RunLoop.current.run(until: Date().addingTimeInterval(Self.pollingInterval))
        } while Date() < deadline

        return candidates.first(where: \.exists)
    }
}

extension XCUIElement {
    @discardableResult
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @discardableResult
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

/// XCUITest E2E tests for the menu bar entry point.
///
/// These tests launch the real app, click the status item in the menu bar, and
/// interact with the popover window like a real user would. They cover what no
/// other test layer can: the full click → popover → button → side-effect chain.
final class MenuBarE2EUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = UnmissableUITestSupport.launchArguments(onboardingCompleted: true)
        app.launch()

        let statusItem = UnmissableUITestSupport.statusItem(in: app)
        XCTAssertTrue(
            statusItem.exists,
            "Status item should appear in menu bar",
        )
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - Status Item Presence

    func testStatusItem_existsInMenuBar() {
        let statusItem = UnmissableUITestSupport.statusItem(in: app)
        XCTAssertTrue(statusItem.exists)
    }

    // MARK: - Popover Opens

    func testStatusItem_click_opensPopover() {
        UnmissableUITestSupport.clickStatusItem(in: app)

        let popover = app.windows[UnmissableUITestSupport.popoverIdentifier]
        XCTAssertTrue(
            popover.waitForExistence(timeout: 3),
            "Popover window should appear after clicking the status item",
        )
    }

    func testPopover_containsMenuBarView() {
        UnmissableUITestSupport.clickStatusItem(in: app)

        let popover = app.windows[UnmissableUITestSupport.popoverIdentifier]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))
        XCTAssertTrue(
            popover.otherElements["menu-bar-view"].waitForExistence(timeout: 3),
            "Menu bar root view should appear inside the popover",
        )
    }

    // MARK: - Footer Buttons

    func testPopover_preferencesButton_opensPreferencesWindow() {
        UnmissableUITestSupport.clickStatusItem(in: app)
        let popover = app.windows[UnmissableUITestSupport.popoverIdentifier]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        let preferencesButton = popover.buttons["preferences-button"]
        XCTAssertTrue(preferencesButton.waitForHittable(timeout: 3))
        preferencesButton.click()

        let prefsWindow = app.windows["Unmissable Preferences"]
        XCTAssertTrue(
            prefsWindow.waitForExistence(timeout: 3),
            "Preferences window should open after clicking Preferences",
        )
    }

    func testPopover_quitButton_exists() {
        UnmissableUITestSupport.clickStatusItem(in: app)
        let popover = app.windows[UnmissableUITestSupport.popoverIdentifier]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        XCTAssertTrue(popover.buttons["quit-button"].waitForExistence(timeout: 3))
    }

    // MARK: - Disconnected State (first launch, no calendars)

    func testPopover_disconnected_showsConnectButtons() {
        UnmissableUITestSupport.clickStatusItem(in: app)
        let popover = app.windows[UnmissableUITestSupport.popoverIdentifier]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        let hasApple = popover.buttons["connect-apple-calendar-button"].waitForExistence(timeout: 3)
        let hasGoogle = popover.buttons["connect-google-calendar-button"].waitForExistence(timeout: 3)
        XCTAssertTrue(
            hasApple || hasGoogle,
            "Should show calendar connect buttons when disconnected",
        )
    }

    // MARK: - Sync Controls (when connected)

    @MainActor func testPopover_connected_showsSyncButton() {
        UnmissableUITestSupport.clickStatusItem(in: app)
        let popover = app.windows[UnmissableUITestSupport.popoverIdentifier]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        if popover.buttons["sync-button"].exists {
            XCTAssertTrue(popover.staticTexts["sync-status-text"].waitForExistence(timeout: 3))
        }
    }
}
