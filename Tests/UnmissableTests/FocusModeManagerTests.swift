@testable import Unmissable
import XCTest

@MainActor
final class FocusModeManagerTests: XCTestCase {
    // MARK: - shouldShowOverlay

    func testShouldShowOverlay_dndOff_returnsTrue() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = false

        XCTAssertTrue(manager.shouldShowOverlay())
    }

    func testShouldShowOverlay_dndOn_overrideEnabled_returnsTrue() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = true
        preferences.setOverrideFocusMode(true)

        XCTAssertTrue(manager.shouldShowOverlay())
    }

    func testShouldShowOverlay_dndOn_overrideDisabled_returnsFalse() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = true
        preferences.setOverrideFocusMode(false)

        XCTAssertFalse(manager.shouldShowOverlay())
    }

    // MARK: - shouldPlaySound

    func testShouldPlaySound_dndOff_returnsTrue() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = false

        XCTAssertTrue(manager.shouldPlaySound())
    }

    func testShouldPlaySound_dndOn_overrideDisabled_returnsFalse() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = true
        preferences.setOverrideFocusMode(false)

        XCTAssertFalse(manager.shouldPlaySound())
    }

    func testShouldPlaySound_delegatesToShouldShowOverlay() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = true
        preferences.setOverrideFocusMode(true)

        XCTAssertEqual(
            manager.shouldPlaySound(),
            manager.shouldShowOverlay(),
            "shouldPlaySound must delegate to shouldShowOverlay",
        )
    }
}
