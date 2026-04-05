import XCTest

/// XCUITest E2E tests for the menu bar entry point and first-launch onboarding flow.
///
/// Launches the real app and interacts with it via accessibility, verifying:
/// 1. Clicking the menu bar icon opens the dropdown popover
/// 2. The welcome modal opens as the frontmost window on first launch
/// 3. The title bar close button dismisses the welcome modal
/// 4. The "Continue" button navigates through the complete onboarding journey
///
/// Launch argument `-hasCompletedOnboarding` controls whether the app behaves
/// as a first launch (shows onboarding) or returning launch (skips it).
/// The value is injected into `UserDefaults.standard` via the argument domain.
///
/// ## Safety discipline for click interactions
///
/// XCUITest synthesises clicks at screen coordinates. If the target window is
/// behind another app's window, the click lands on the wrong window. To prevent
/// accidents, every test that performs a click first waits for the target
/// control to become hittable (the regression check that the window IS in
/// front), then clicks directly.
///
/// The hittable assertion is the real test — it fails when the production bug is
/// present (window opens behind other windows) and passes after the fix.
/// Once the control is hittable, an extra app activation step can interfere with
/// the synthesized event target, so the tests click directly.
final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    /// Launches the app configured for UI testing.
    /// - Parameter onboardingCompleted: `false` simulates first launch (onboarding window appears).
    private func launchApp(onboardingCompleted: Bool) {
        app = XCUIApplication()
        app.launchArguments = UnmissableUITestSupport.launchArguments(
            onboardingCompleted: onboardingCompleted,
            regularActivation: true,
        )
        app.launch()
        app.activate()
    }

    /// Asserts the element is hittable (not behind another window), then clicks it.
    ///
    /// The hittable assertion is the regression gate.
    private func assertHittableThenClick(_ element: XCUIElement, label: String) {
        XCTAssertTrue(
            element.waitForHittable(timeout: 5),
            "\(label) must become hittable — window must be frontmost and interactive",
        )
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    // MARK: - 1. Menu Bar Icon Opens Dropdown

    func testMenuBarIcon_click_opensDropdownMenu() {
        launchApp(onboardingCompleted: true)

        UnmissableUITestSupport.clickStatusItem(in: app)

        // Allow extra time for the popover window to appear.
        let popover = app.windows[UnmissableUITestSupport.popoverIdentifier]
        XCTAssertTrue(
            popover.waitForExistence(timeout: 10),
            "Dropdown menu should appear after clicking the menu bar icon",
        )
    }

    // MARK: - 2. Welcome Modal Opens on Top of All Windows

    /// Regression test for the "window opens behind other apps" bug.
    ///
    /// Root cause: activateWindow() called NSApp.activate() BEFORE makeKeyAndOrderFront.
    /// NSApp.activate() is asynchronous — the app was not yet the active process when
    /// makeKeyAndOrderFront ran, so the window appeared at the correct layer within the
    /// app but behind other apps' windows at the screen level.
    ///
    /// Fix: makeKeyAndOrderFront first (registers the window), then NSApp.activate()
    /// (brings the now-registered frontmost window to the top of the screen stack).
    ///
    /// The first actionable control becomes non-hittable if the window ends up
    /// behind another app, making it a direct regression check for this bug.
    func testWelcomeModal_opensOnTopOfAllWindows() {
        launchApp(onboardingCompleted: false)

        let window = app.windows["Welcome to Unmissable"]
        XCTAssertTrue(
            window.waitForExistence(timeout: 10),
            "Welcome modal should appear on first launch",
        )

        let continueButton = window.buttons["onboarding-continue-button"]
        XCTAssertTrue(
            continueButton.waitForExistence(timeout: 3),
            "Welcome screen content should be visible",
        )
        XCTAssertTrue(
            continueButton.waitForHittable(timeout: 5),
            "Continue button must be hittable — confirms the window is frontmost and interactive",
        )
    }

    // MARK: - 3. Close Button Dismisses Modal

    func testWelcomeModal_titleBarCloseButton_dismissesWindow() {
        launchApp(onboardingCompleted: false)

        let window = app.windows["Welcome to Unmissable"]
        XCTAssertTrue(
            window.waitForExistence(timeout: 10),
            "Welcome modal should appear on first launch",
        )

        let closeButton = window.buttons["_XCUI:CloseWindow"]
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 3),
            "Title bar close button should exist (.closable style mask)",
        )

        // Hittability asserts the window is frontmost (regression check).
        assertHittableThenClick(closeButton, label: "Close button")

        // The onboarding window should no longer exist after the title-bar close.
        XCTAssertTrue(
            window.waitForNonExistence(timeout: 10),
            "Welcome modal should disappear after closing via title bar",
        )
    }

    // MARK: - 4. Continue Button Navigates Through Onboarding Journey

    func testWelcomeModal_continueButton_navigatesThroughOnboardingJourney() {
        launchApp(onboardingCompleted: false)

        let window = app.windows["Welcome to Unmissable"]
        XCTAssertTrue(
            window.waitForExistence(timeout: 10),
            "Welcome modal should appear on first launch",
        )

        // --- Screen 1: Welcome ---
        let continueButton = window.buttons["onboarding-continue-button"]
        XCTAssertTrue(
            continueButton.waitForExistence(timeout: 3),
            "Continue button should be visible on the Welcome screen",
        )
        assertHittableThenClick(continueButton, label: "Continue button")

        // --- Screen 2: Connect Calendar ---
        let skipButton = window.buttons["onboarding-skip-button"]
        XCTAssertTrue(
            skipButton.waitForExistence(timeout: 5),
            "Should navigate to Connect Calendar screen after clicking Continue",
        )
        assertHittableThenClick(skipButton, label: "Skip button")

        // --- Screen 3: All Set ---
        let doneButton = window.buttons["onboarding-done-button"]
        XCTAssertTrue(
            doneButton.waitForExistence(timeout: 5),
            "Should navigate to All Set screen after skipping calendar connection",
        )
        assertHittableThenClick(doneButton, label: "Done button")

        XCTAssertTrue(
            window.waitForNonExistence(timeout: 10),
            "Welcome modal should close after completing the onboarding journey",
        )
    }

    // MARK: - 5. Menu Bar Icon Responds While Onboarding Is Showing

    /// Regression test: clicking the menu bar icon must work while the onboarding
    /// window is open and the activation policy is temporarily .regular.
    func testMenuBarIcon_clickable_whileOnboardingIsShowing() {
        launchApp(onboardingCompleted: false)

        let onboardingWindow = app.windows["Welcome to Unmissable"]
        XCTAssertTrue(
            onboardingWindow.waitForExistence(timeout: 10),
            "Onboarding window must be showing for this test to be meaningful",
        )

        UnmissableUITestSupport.clickStatusItem(in: app)

        let popover = app.windows[UnmissableUITestSupport.popoverIdentifier]
        XCTAssertTrue(
            popover.waitForExistence(timeout: 10),
            "Clicking the menu bar icon must open the popover while onboarding is showing",
        )
    }
}
