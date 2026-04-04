import Foundation
import TestSupport
@testable import Unmissable
import XCTest

/// Tests smart alert suppression — overlay is skipped when the user already has
/// the meeting's video app (or browser for Meet) in the foreground.
@MainActor
final class SmartSuppressionTests: XCTestCase {
    // MARK: - Provider Bundle IDs

    func testZoomProvider_hasCorrectBundleIdentifiers() {
        XCTAssertEqual(Provider.zoom.knownBundleIdentifiers, ["us.zoom.xos"])
    }

    func testTeamsProvider_hasBothBundleIdentifiers() {
        XCTAssertEqual(
            Provider.teams.knownBundleIdentifiers,
            ["com.microsoft.teams", "com.microsoft.teams2"],
        )
    }

    func testWebexProvider_hasBothBundleIdentifiers() {
        XCTAssertEqual(
            Provider.webex.knownBundleIdentifiers,
            ["com.webex.meetingmanager", "com.cisco.webexmeetings"],
        )
    }

    func testMeetProvider_returnsEmptyBundleIdentifiers() {
        XCTAssertEqual(Provider.meet.knownBundleIdentifiers, [])
    }

    func testGenericProvider_returnsEmptyBundleIdentifiers() {
        XCTAssertEqual(Provider.generic.knownBundleIdentifiers, [])
    }

    // MARK: - Foreground App Detector (Stubbed)

    func testStubDetector_meetingAppInForeground_returnsFalseByDefault() {
        let detector = TestSafeForegroundAppDetector()
        XCTAssertFalse(detector.isMeetingAppInForeground(for: .zoom))
    }

    func testStubDetector_meetingAppInForeground_returnsTrueWhenSet() {
        let detector = TestSafeForegroundAppDetector()
        detector.meetingAppInForeground = true
        XCTAssertTrue(detector.isMeetingAppInForeground(for: .zoom))
    }

    func testStubDetector_browserInForeground_returnsFalseByDefault() {
        let detector = TestSafeForegroundAppDetector()
        XCTAssertFalse(detector.isBrowserInForeground())
    }

    func testStubDetector_browserInForeground_returnsTrueWhenSet() {
        let detector = TestSafeForegroundAppDetector()
        detector.browserInForeground = true
        XCTAssertTrue(detector.isBrowserInForeground())
    }

    // MARK: - Smart Suppression Integration (via TestSafe)

    func testShowOverlay_suppressedWhenNativeAppInForeground() {
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

        XCTAssertFalse(
            overlay.isOverlayVisible,
            "Overlay should be suppressed when meeting app is in foreground",
        )
        XCTAssertNil(overlay.activeEvent)
    }

    func testShowOverlay_notSuppressedWhenFromSnooze() {
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

        XCTAssertTrue(
            overlay.isOverlayVisible,
            "fromSnooze alerts must never be suppressed",
        )
        XCTAssertEqual(overlay.activeEvent?.id, event.id)
    }

    func testShowOverlay_notSuppressedWhenPreferenceDisabled() {
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

        XCTAssertTrue(
            overlay.isOverlayVisible,
            "Overlay should not be suppressed when smart suppression is disabled",
        )
        XCTAssertEqual(overlay.activeEvent?.id, event.id)
    }

    func testShowOverlay_notSuppressedWhenAppNotInForeground() {
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

        XCTAssertTrue(
            overlay.isOverlayVisible,
            "Overlay should show when meeting app is not in foreground",
        )
        XCTAssertEqual(overlay.activeEvent?.id, event.id)
    }

    func testShowOverlay_meetProviderSuppressedWhenBrowserInForeground() {
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

        XCTAssertFalse(
            overlay.isOverlayVisible,
            "Google Meet overlay should be suppressed when browser is in foreground",
        )
    }

    func testShowOverlay_nonMeetProviderNotSuppressedByBrowser() {
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

        XCTAssertTrue(
            overlay.isOverlayVisible,
            "Zoom overlay should not be suppressed just because a browser is in foreground",
        )
    }

    func testShowOverlay_noProviderNotSuppressed() {
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

        XCTAssertTrue(
            overlay.isOverlayVisible,
            "Events without a provider should never be suppressed",
        )
    }

    // MARK: - Preference Persistence

    func testSmartSuppressionPreference_defaultsToTrue() {
        let prefs = TestUtilities.createTestPreferencesManager()
        XCTAssertTrue(prefs.smartSuppression)
    }

    func testSmartSuppressionPreference_persistsWhenDisabled() throws {
        let suiteName = "com.unmissable.test.\(UUID().uuidString)"
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
        )

        prefs.setSmartSuppression(false)
        XCTAssertFalse(prefs.smartSuppression)

        // Reload preferences from the same UserDefaults
        let prefs2 = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
        )
        XCTAssertFalse(
            prefs2.smartSuppression,
            "Smart suppression should persist across PreferencesManager instances",
        )
    }
}
