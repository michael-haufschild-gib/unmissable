import Foundation
import Testing
@testable import Unmissable

@MainActor
struct FocusModeManagerTests {
    // MARK: - shouldShowOverlay

    @Test
    func shouldShowOverlay_dndOff_returnsTrue() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = false

        #expect(manager.shouldShowOverlay())
    }

    @Test
    func shouldShowOverlay_dndOn_overrideEnabled_returnsTrue() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = true
        preferences.setOverrideFocusMode(true)

        #expect(manager.shouldShowOverlay())
    }

    @Test
    func shouldShowOverlay_dndOn_overrideDisabled_returnsFalse() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = true
        preferences.setOverrideFocusMode(false)

        #expect(!manager.shouldShowOverlay())
    }

    // MARK: - shouldPlaySound

    @Test
    func shouldPlaySound_dndOff_returnsTrue() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = false

        #expect(manager.shouldPlaySound())
    }

    @Test
    func shouldPlaySound_dndOn_overrideDisabled_returnsFalse() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = true
        preferences.setOverrideFocusMode(false)

        #expect(!manager.shouldPlaySound())
    }

    @Test
    func shouldPlaySound_delegatesToShouldShowOverlay() {
        let preferences = TestUtilities.createTestPreferencesManager()
        let manager = FocusModeManager(preferencesManager: preferences, isTestMode: true)
        manager.isDoNotDisturbEnabled = true
        preferences.setOverrideFocusMode(true)

        #expect(
            manager.shouldPlaySound() == manager.shouldShowOverlay(),
            "shouldPlaySound must delegate to shouldShowOverlay",
        )
    }
}
