import Foundation
import Testing
@testable import Unmissable

/// Tests smart alert suppression — overlay is skipped when the user already has
/// the meeting's video app (or browser for Meet) in the foreground.
@MainActor
struct SmartSuppressionTests {
    // MARK: - Provider Bundle IDs

    @Test
    func zoomProvider_hasCorrectBundleIdentifiers() {
        #expect(Provider.zoom.knownBundleIdentifiers == ["us.zoom.xos"])
    }

    @Test
    func teamsProvider_hasBothBundleIdentifiers() {
        #expect(
            Provider.teams.knownBundleIdentifiers == ["com.microsoft.teams", "com.microsoft.teams2"],
        )
    }

    @Test
    func webexProvider_hasBothBundleIdentifiers() {
        #expect(
            Provider.webex.knownBundleIdentifiers == ["com.webex.meetingmanager", "com.cisco.webexmeetings"],
        )
    }

    @Test
    func meetProvider_returnsEmptyBundleIdentifiers() {
        #expect(Provider.meet.knownBundleIdentifiers.isEmpty)
    }

    @Test
    func genericProvider_returnsEmptyBundleIdentifiers() {
        #expect(Provider.generic.knownBundleIdentifiers.isEmpty)
    }

    // MARK: - Foreground App Detector (Stubbed)

    @Test
    func stubDetector_meetingAppInForeground_returnsFalseByDefault() {
        let detector = TestSafeForegroundAppDetector()
        #expect(!detector.isMeetingAppInForeground(for: .zoom))
    }

    @Test
    func stubDetector_meetingAppInForeground_returnsTrueWhenSet() {
        let detector = TestSafeForegroundAppDetector()
        detector.meetingAppInForeground = true
        #expect(detector.isMeetingAppInForeground(for: .zoom))
    }

    @Test
    func stubDetector_browserInForeground_returnsFalseByDefault() {
        let detector = TestSafeForegroundAppDetector()
        #expect(!detector.isBrowserInForeground())
    }

    @Test
    func stubDetector_browserInForeground_returnsTrueWhenSet() {
        let detector = TestSafeForegroundAppDetector()
        detector.browserInForeground = true
        #expect(detector.isBrowserInForeground())
    }

    // MARK: - Smart Suppression Integration (via TestSafe)

    @Test
    func showOverlay_suppressedWhenNativeAppInForeground() {
        let detector = TestSafeForegroundAppDetector()
        detector.meetingAppInForeground = true
        let prefs = TestUtilities.createTestPreferencesManager()
        prefs.setSmartSuppression(true)

        let overlay = TestSafeOverlayManager(
            isTestEnvironment: true,
            foregroundAppDetector: detector,
            preferencesManager: prefs,
        )

        let event = TestUtilities.createTestEvent(provider: .zoom)
        overlay.showOverlay(for: event, fromSnooze: false)

        #expect(
            !overlay.isOverlayVisible,
            "Overlay should be suppressed when meeting app is in foreground",
        )
        #expect(overlay.activeEvent == nil)
    }

    @Test
    func showOverlay_notSuppressedWhenFromSnooze() {
        let detector = TestSafeForegroundAppDetector()
        detector.meetingAppInForeground = true
        let prefs = TestUtilities.createTestPreferencesManager()
        prefs.setSmartSuppression(true)

        let overlay = TestSafeOverlayManager(
            isTestEnvironment: true,
            foregroundAppDetector: detector,
            preferencesManager: prefs,
        )

        let event = TestUtilities.createTestEvent(provider: .zoom)
        overlay.showOverlay(for: event, fromSnooze: true)

        #expect(
            overlay.isOverlayVisible,
            "fromSnooze alerts must never be suppressed",
        )
        #expect(overlay.activeEvent?.id == event.id)
    }

    @Test
    func showOverlay_notSuppressedWhenPreferenceDisabled() {
        let detector = TestSafeForegroundAppDetector()
        detector.meetingAppInForeground = true
        let prefs = TestUtilities.createTestPreferencesManager()
        prefs.setSmartSuppression(false)

        let overlay = TestSafeOverlayManager(
            isTestEnvironment: true,
            foregroundAppDetector: detector,
            preferencesManager: prefs,
        )

        let event = TestUtilities.createTestEvent(provider: .zoom)
        overlay.showOverlay(for: event, fromSnooze: false)

        #expect(
            overlay.isOverlayVisible,
            "Overlay should not be suppressed when smart suppression is disabled",
        )
        #expect(overlay.activeEvent?.id == event.id)
    }

    @Test
    func showOverlay_notSuppressedWhenAppNotInForeground() {
        let detector = TestSafeForegroundAppDetector()
        detector.meetingAppInForeground = false
        let prefs = TestUtilities.createTestPreferencesManager()
        prefs.setSmartSuppression(true)

        let overlay = TestSafeOverlayManager(
            isTestEnvironment: true,
            foregroundAppDetector: detector,
            preferencesManager: prefs,
        )

        let event = TestUtilities.createTestEvent(provider: .zoom)
        overlay.showOverlay(for: event, fromSnooze: false)

        #expect(
            overlay.isOverlayVisible,
            "Overlay should show when meeting app is not in foreground",
        )
        #expect(overlay.activeEvent?.id == event.id)
    }

    @Test
    func showOverlay_meetProviderSuppressedWhenBrowserInForeground() {
        let detector = TestSafeForegroundAppDetector()
        detector.browserInForeground = true
        let prefs = TestUtilities.createTestPreferencesManager()
        prefs.setSmartSuppression(true)

        let overlay = TestSafeOverlayManager(
            isTestEnvironment: true,
            foregroundAppDetector: detector,
            preferencesManager: prefs,
        )

        let event = TestUtilities.createTestEvent(provider: .meet)
        overlay.showOverlay(for: event, fromSnooze: false)

        #expect(
            !overlay.isOverlayVisible,
            "Google Meet overlay should be suppressed when browser is in foreground",
        )
    }

    @Test
    func showOverlay_nonMeetProviderNotSuppressedByBrowser() {
        let detector = TestSafeForegroundAppDetector()
        detector.browserInForeground = true
        detector.meetingAppInForeground = false
        let prefs = TestUtilities.createTestPreferencesManager()
        prefs.setSmartSuppression(true)

        let overlay = TestSafeOverlayManager(
            isTestEnvironment: true,
            foregroundAppDetector: detector,
            preferencesManager: prefs,
        )

        let event = TestUtilities.createTestEvent(provider: .zoom)
        overlay.showOverlay(for: event, fromSnooze: false)

        #expect(
            overlay.isOverlayVisible,
            "Zoom overlay should not be suppressed just because a browser is in foreground",
        )
    }

    @Test
    func showOverlay_noProviderNotSuppressed() {
        let detector = TestSafeForegroundAppDetector()
        detector.meetingAppInForeground = true
        detector.browserInForeground = true
        let prefs = TestUtilities.createTestPreferencesManager()
        prefs.setSmartSuppression(true)

        let overlay = TestSafeOverlayManager(
            isTestEnvironment: true,
            foregroundAppDetector: detector,
            preferencesManager: prefs,
        )

        let event = TestUtilities.createTestEvent(provider: nil)
        overlay.showOverlay(for: event, fromSnooze: false)

        #expect(
            overlay.isOverlayVisible,
            "Events without a provider should never be suppressed",
        )
    }

    // MARK: - Preference Persistence

    @Test
    func smartSuppressionPreference_defaultsToTrue() {
        let prefs = TestUtilities.createTestPreferencesManager()
        #expect(prefs.smartSuppression)
    }

    @Test
    func smartSuppressionPreference_persistsWhenDisabled() throws {
        let suiteName = "com.unmissable.test.\(UUID().uuidString)"
        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
        )

        prefs.setSmartSuppression(false)
        #expect(!prefs.smartSuppression)

        // Reload preferences from the same UserDefaults
        let prefs2 = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
        )
        #expect(
            !prefs2.smartSuppression,
            "Smart suppression should persist across PreferencesManager instances",
        )
    }
}
