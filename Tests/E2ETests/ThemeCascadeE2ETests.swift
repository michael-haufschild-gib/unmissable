import Foundation
import TestSupport
@testable import Unmissable
import XCTest

/// E2E tests for theme and accent color changes cascading through the full stack:
/// UserDefaults → PreferencesManager → ThemeManager → DesignTokens → environment.
@MainActor
final class ThemeCascadeE2ETests: XCTestCase {
    private var env: E2ETestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        env = try await E2ETestEnvironment()
    }

    override func tearDown() async throws {
        env.tearDown()
        env = nil
        try await super.tearDown()
    }

    // MARK: - Theme Mode Persistence

    func testSetThemeModePersistsToUserDefaults() throws {
        let prefs = env.preferencesManager
        let suiteName = "com.unmissable.e2e.theme-persist-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let themeManager = ThemeManager()
        let isolatedPrefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        isolatedPrefs.setThemeMode(.darkPurple)
        XCTAssertEqual(isolatedPrefs.themeMode, .darkPurple)
        XCTAssertEqual(
            testDefaults.string(forKey: "themeMode"),
            "darkPurple",
            "ThemeMode should be persisted to UserDefaults",
        )

        // Verify ThemeManager was updated
        XCTAssertEqual(themeManager.themeMode, .darkPurple)
        XCTAssertEqual(themeManager.resolvedTheme, .darkPurple)
    }

    func testSetAccentColorPersistsToUserDefaults() throws {
        let suiteName = "com.unmissable.e2e.accent-persist-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let themeManager = ThemeManager()
        let isolatedPrefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        isolatedPrefs.setAccentColor(.magenta)
        XCTAssertEqual(isolatedPrefs.accentColor, .magenta)
        XCTAssertEqual(
            testDefaults.string(forKey: "accentColor"),
            "magenta",
            "AccentColor should be persisted to UserDefaults",
        )

        // Verify ThemeManager was updated
        XCTAssertEqual(themeManager.accentColor, .magenta)
    }

    // MARK: - Theme Mode → Resolved Theme Cascade

    func testAllThemeModesResolveCorrectly() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.resolve-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        let expectations: [(ThemeMode, ResolvedTheme)] = [
            (.light, .light),
            (.darkBlue, .darkBlue),
            (.darkPurple, .darkPurple),
            (.darkBrown, .darkBrown),
            (.darkBlack, .darkBlack),
        ]

        for (mode, expected) in expectations {
            prefs.setThemeMode(mode)
            XCTAssertEqual(
                themeManager.resolvedTheme,
                expected,
                "ThemeMode.\(mode) should resolve to .\(expected)",
            )
        }

        // System mode falls back to darkBlue in test environment (no NSApp)
        prefs.setThemeMode(.system)
        XCTAssertEqual(themeManager.resolvedTheme, .darkBlue)
    }

    // MARK: - Design Tokens Reflect Theme + Accent

    func testDesignTokensReflectThemeAndAccentChanges() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.tokens-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        // Set dark purple + orange accent
        prefs.setThemeMode(.darkPurple)
        prefs.setAccentColor(.orange)

        let tokens = DesignTokens.tokens(
            for: themeManager.resolvedTheme,
            accent: themeManager.accentColor,
        )

        // Accent should be orange
        XCTAssertEqual(tokens.colors.accent, AccentColor.orange.color)
        XCTAssertEqual(tokens.colors.accentHover, AccentColor.orange.hoverColor)
        XCTAssertEqual(tokens.colors.accentPressed, AccentColor.orange.pressedColor)

        // Now switch to dark blue + cyan
        prefs.setThemeMode(.darkBlue)
        prefs.setAccentColor(.cyan)

        let tokens2 = DesignTokens.tokens(
            for: themeManager.resolvedTheme,
            accent: themeManager.accentColor,
        )

        // Background should differ (different theme)
        XCTAssertNotEqual(
            tokens.colors.background,
            tokens2.colors.background,
            "DarkPurple and DarkBlue should have different backgrounds",
        )

        // Accent should be cyan now
        XCTAssertEqual(tokens2.colors.accent, AccentColor.cyan.color)
    }

    // MARK: - Legacy Migration

    func testLegacyDarkThemeMigratesToDarkBlue() throws {
        let suiteName = "com.unmissable.e2e.migrate-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        // Simulate old stored value
        testDefaults.set("dark", forKey: "appearanceTheme")

        let themeManager = ThemeManager()
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        XCTAssertEqual(
            prefs.themeMode,
            .darkBlue,
            "Legacy 'dark' should migrate to 'darkBlue'",
        )
        XCTAssertEqual(themeManager.resolvedTheme, .darkBlue)

        // Verify new key was written
        XCTAssertEqual(testDefaults.string(forKey: "themeMode"), "darkBlue")
    }

    func testLegacyLightThemeMigratesToLight() throws {
        let suiteName = "com.unmissable.e2e.migrate-light-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        testDefaults.set("light", forKey: "appearanceTheme")

        let themeManager = ThemeManager()
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        XCTAssertEqual(prefs.themeMode, .light)
        XCTAssertEqual(themeManager.resolvedTheme, .light)
    }

    func testLegacySystemThemeMigratesToSystem() throws {
        let suiteName = "com.unmissable.e2e.migrate-system-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        testDefaults.set("system", forKey: "appearanceTheme")

        let themeManager = ThemeManager()
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        XCTAssertEqual(prefs.themeMode, .system)
    }

    // MARK: - Accent + Theme Independence

    func testAccentColorIsIndependentOfThemeMode() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.independence-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        prefs.setAccentColor(.red)
        prefs.setThemeMode(.darkBrown)

        XCTAssertEqual(themeManager.accentColor, .red)
        XCTAssertEqual(themeManager.resolvedTheme, .darkBrown)

        // Changing theme should not affect accent
        prefs.setThemeMode(.light)
        XCTAssertEqual(
            themeManager.accentColor,
            .red,
            "Accent should not change when theme mode changes",
        )

        // Changing accent should not affect theme
        prefs.setAccentColor(.violet)
        XCTAssertEqual(
            themeManager.resolvedTheme,
            .light,
            "Theme should not change when accent changes",
        )
    }

    // MARK: - Full Cycle: All Theme × Accent Combinations

    func testAllThemeAccentCombinationsProduceValidTokens() {
        let darkThemes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        let accents = AccentColor.allCases

        for theme in darkThemes {
            for accent in accents {
                let tokens = DesignTokens.tokens(for: theme, accent: accent)

                // Every combination must produce non-equal bg vs text
                XCTAssertNotEqual(
                    tokens.colors.background,
                    tokens.colors.textPrimary,
                    "Theme \(theme) + accent \(accent): bg must differ from text",
                )

                // Accent must match the input accent
                XCTAssertEqual(
                    tokens.colors.accent,
                    accent.color,
                    "Theme \(theme) + accent \(accent): accent color must match",
                )
            }
        }
    }

    // MARK: - Bindings

    func testThemeModeBindingUpdatesThemeManager() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.binding-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        // Simulate SwiftUI binding set
        prefs.themeModeBinding.wrappedValue = .darkBlack
        XCTAssertEqual(prefs.themeMode, .darkBlack)
        XCTAssertEqual(themeManager.resolvedTheme, .darkBlack)
    }

    func testAccentColorBindingUpdatesThemeManager() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.accent-binding-\(UUID().uuidString)"

        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        prefs.accentColorBinding.wrappedValue = .green
        XCTAssertEqual(prefs.accentColor, .green)
        XCTAssertEqual(themeManager.accentColor, .green)
    }
}
