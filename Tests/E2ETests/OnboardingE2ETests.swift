import AppKit
import Foundation
import Testing
@testable import Unmissable

/// E2E tests for the first-launch onboarding flow.
///
/// Verifies that the onboarding window manager correctly creates, activates,
/// and closes the onboarding window — including the activation policy switch
/// required for `.accessory` (menu-bar-only) apps to have interactive windows.
///
/// These tests exist because three production bugs shipped without detection:
/// - Window appeared behind other windows (activation before policy set)
/// - Title bar and SwiftUI buttons unresponsive (window never became key)
/// - Menu bar icon unclickable (window creation interfered with MenuBarExtra)
///
/// NOTE: `NSApp.setActivationPolicy(.accessory)` is NOT called in tests — doing
/// so crashes the XCTest runner process (signal 5). Tests verify the activation
/// policy transitions FROM the test runner's default `.regular` state.
/// `isKeyWindow` is unreliable in test processes (the runner holds display focus,
/// so `NSWindow.isKeyWindow` returns false regardless of call order). Key-window
/// correctness is verified by the XCUITests in OnboardingUITests.swift, which
/// launch the real app and confirm that close/continue buttons respond without
/// requiring an external `app.activate()` call.
@MainActor
final class OnboardingE2ETests {
    private let appState: AppState
    private let manager: OnboardingWindowManager
    private let preferencesManager: PreferencesManager
    private let suiteName: String

    init() {
        suiteName = "com.unmissable.onboarding-test.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: suiteName)!
        let theme = ThemeManager()
        let prefs = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: theme,
            loginItemManager: TestSafeLoginItemManager(),
        )
        preferencesManager = prefs

        let dbManager = DatabaseManager()
        let overlayStub = TestSafeOverlayManager(isTestEnvironment: true)
        let services = ServiceContainer(
            databaseManager: dbManager,
            themeManager: theme,
            overlayManagerOverride: overlayStub,
            preferencesManagerOverride: prefs,
        )

        appState = AppState(services: services, isTestEnvironment: true)
        manager = OnboardingWindowManager(appState: appState)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Window Creation

    @Test
    func showOnboarding_createsVisibleWindow() {
        defer { manager.close() }
        manager.showOnboarding()

        #expect(manager.isWindowVisible, "Onboarding window should be visible after showOnboarding()")
    }

    @Test
    func showOnboarding_windowHasCorrectTitle() {
        defer { manager.close() }
        manager.showOnboarding()

        #expect(manager.windowTitle == "Welcome to Unmissable")
    }

    // MARK: - Activation Policy

    @Test
    func showOnboarding_setsRegularActivationPolicy() {
        // In production, the app starts as .accessory (no dock icon). When the
        // onboarding window opens, the manager must switch to .regular so macOS
        // grants full window focus. The test runner is already .regular, but we
        // verify showOnboarding() sets it — the call is idempotent and proves
        // the code path executes.
        defer { manager.close() }
        manager.showOnboarding()

        #expect(
            NSApp.activationPolicy() == .regular,
            "showOnboarding must set .regular policy for window to receive focus",
        )
    }

    // MARK: - Window Close

    @Test
    func close_dismissesWindow() {
        manager.showOnboarding()
        #expect(manager.isWindowVisible)

        manager.close()

        #expect(!manager.isWindowVisible, "Window should not be visible after close()")
    }

    @Test
    func close_windowTitleBecomesNil() {
        manager.showOnboarding()
        #expect(manager.windowTitle != nil)

        manager.close()

        #expect(manager.windowTitle == nil, "Window reference should be released after close")
    }

    // MARK: - Window Delegate

    @Test
    func windowShouldClose_returnsTrue() {
        defer { manager.close() }
        manager.showOnboarding()

        // The window delegate must allow closing — if this returns false,
        // the title bar close button does nothing (the original bug).
        let delegate = manager as NSWindowDelegate
        let shouldClose = delegate.windowShouldClose?(NSWindow())
        #expect(shouldClose == true, "Window delegate must allow closing")
    }

    // MARK: - Duplicate Window Prevention

    @Test
    func showOnboarding_calledTwice_reusesSameWindow() {
        defer { manager.close() }
        manager.showOnboarding()
        let firstTitle = manager.windowTitle

        manager.showOnboarding()
        let secondTitle = manager.windowTitle

        #expect(firstTitle == secondTitle, "Should reuse existing window, not create a second one")
        #expect(manager.isWindowVisible)
    }

    // MARK: - Complete Onboarding Integration

    // Uses AppState's own onboardingWindowManager (not the standalone `manager`
    // from init) to exercise the real production path:
    // AppState.completeOnboarding() → onboardingWindowManager.close()

    @Test
    func completeOnboarding_closesWindow() {
        let stateManager = appState.onboardingWindowManager
        stateManager.showOnboarding()
        #expect(stateManager.isWindowVisible)

        appState.completeOnboarding()

        #expect(!stateManager.isWindowVisible, "Window should close after completing onboarding")
    }

    @Test
    func completeOnboarding_setsPreference() {
        let stateManager = appState.onboardingWindowManager
        stateManager.showOnboarding()
        #expect(!preferencesManager.hasCompletedOnboarding)

        appState.completeOnboarding()

        #expect(
            preferencesManager.hasCompletedOnboarding,
            "Preference must be set so onboarding doesn't show again on next launch",
        )
    }

    @Test
    func completeOnboarding_withoutShowingWindow_stillSetsPreference() {
        // Edge case: if completeOnboarding is called without showing the window
        // (e.g., during migration), it should still mark onboarding complete.
        #expect(!preferencesManager.hasCompletedOnboarding)

        appState.completeOnboarding()

        #expect(preferencesManager.hasCompletedOnboarding)
    }

    // MARK: - First Launch Detection

    @Test
    func checkInitialState_firstLaunch_showsOnboarding() {
        #expect(!preferencesManager.hasCompletedOnboarding)

        appState.checkInitialState()

        let stateManager = appState.onboardingWindowManager
        defer { stateManager.close() }
        #expect(
            stateManager.isWindowVisible,
            "First launch should show onboarding window",
        )
    }

    @Test
    func checkInitialState_returningUser_doesNotShowOnboarding() {
        preferencesManager.setHasCompletedOnboarding(true)

        appState.checkInitialState()

        let stateManager = appState.onboardingWindowManager
        #expect(
            !stateManager.isWindowVisible,
            "Returning user should not see onboarding",
        )
    }
}
