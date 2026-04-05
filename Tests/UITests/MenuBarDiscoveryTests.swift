import XCTest

/// Discovery spike to map the accessibility tree before writing full E2E tests.
///
/// Run this once via xcodebuild to discover where the NSStatusItem button and
/// popover window live in XCUITest's element hierarchy. The output tells you:
/// - Whether `app.buttons["unmissable-status-item"]` finds the status item
/// - Whether `app.windows["unmissable-popover"]` finds the popover after click
/// - What element types (`.buttons`, `.statusItems`, `.menuBars.buttons`) work
///
/// **Not a regression test** — safe to delete once the queries are confirmed.
final class MenuBarDiscoveryTests: XCTestCase {
    func testDiscoverAccessibilityTree() throws {
        // This is a one-shot spike test for discovering the accessibility tree.
        // It is not a regression test and is skipped by default in CI.
        // Set the environment variable to run it locally:
        //   RUN_DISCOVERY_TESTS=1 xcodebuild test -scheme UnmissableUITests ...
        guard ProcessInfo.processInfo.environment["RUN_DISCOVERY_TESTS"] != nil else {
            throw XCTSkip("Set RUN_DISCOVERY_TESTS=1 to run this discovery spike")
        }
        let app = XCUIApplication()
        app.launchArguments = UnmissableUITestSupport.launchArguments(onboardingCompleted: true)
        app.launch()
        let resolvedStatusItem = UnmissableUITestSupport.statusItem(in: app)

        print("=== APP TREE ===")
        print(app.debugDescription)

        let byIdentifier = app.buttons["unmissable-status-item"]
        print("By identifier exists: \(byIdentifier.exists)")
        print("Resolved status item exists: \(resolvedStatusItem.exists)")

        let menuBarButtons = app.menuBars.buttons
        print("Menu bar buttons count: \(menuBarButtons.count)")
        for i in 0 ..< menuBarButtons.count {
            let btn = menuBarButtons.element(boundBy: i)
            print("  Button \(i): \(btn.identifier) / \(btn.label)")
        }

        let statusItems = app.statusItems
        print("Status items count: \(statusItems.count)")

        // If status item not found via app, try system UI server
        if !byIdentifier.exists {
            let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
            let systemStatusItem = systemUI.buttons["unmissable-status-item"]
            print("SystemUI status item exists: \(systemStatusItem.exists)")

            let controlCenter = XCUIApplication(bundleIdentifier: "com.apple.controlcenter")
            let ccStatusItem = controlCenter.buttons["unmissable-status-item"]
            print("ControlCenter status item exists: \(ccStatusItem.exists)")
        }

        if resolvedStatusItem.exists {
            resolvedStatusItem.click()
            let popover = app.windows[UnmissableUITestSupport.popoverIdentifier]
            print("Popover wait result: \(popover.waitForExistence(timeout: 3))")
            print("=== AFTER CLICK ===")
            print(app.debugDescription)
        }
    }
}
