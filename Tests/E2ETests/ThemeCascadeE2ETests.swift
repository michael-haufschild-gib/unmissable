import Foundation
import Testing
@testable import Unmissable

/// E2E tests for theme and accent color changes cascading through the full stack:
/// UserDefaults → PreferencesManager → ThemeManager → DesignTokens → environment.
@MainActor
struct ThemeCascadeE2ETests {
    private let env: E2ETestEnvironment

    init() async throws {
        env = try await E2ETestEnvironment()
    }

    // MARK: - Theme Mode Persistence

    @Test
    func setThemeModePersistsToUserDefaults() throws {
        let suiteName = "com.unmissable.e2e.theme-persist-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        let themeManager = ThemeManager()
        let isolatedPrefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        isolatedPrefs.setThemeMode(.darkPurple)
        #expect(isolatedPrefs.themeMode == .darkPurple)
        #expect(
            testDefaults.string(forKey: "themeMode") == "darkPurple",
            "ThemeMode should be persisted to UserDefaults",
        )

        // Verify ThemeManager was updated
        #expect(themeManager.themeMode == .darkPurple)
        #expect(themeManager.resolvedTheme == .darkPurple)
    }

    @Test
    func setAccentColorPersistsToUserDefaults() throws {
        let suiteName = "com.unmissable.e2e.accent-persist-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        let themeManager = ThemeManager()
        let isolatedPrefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        isolatedPrefs.setAccentColor(.magenta)
        #expect(isolatedPrefs.accentColor == .magenta)
        #expect(
            testDefaults.string(forKey: "accentColor") == "magenta",
            "AccentColor should be persisted to UserDefaults",
        )

        // Verify ThemeManager was updated
        #expect(themeManager.accentColor == .magenta)
    }

    // MARK: - Theme Mode → Resolved Theme Cascade

    @Test
    func allThemeModesResolveCorrectly() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.resolve-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
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
            #expect(
                themeManager.resolvedTheme == expected,
                "ThemeMode.\(mode) should resolve to .\(expected)",
            )
        }

        // System mode falls back to darkBlue in test environment (no NSApp)
        prefs.setThemeMode(.system)
        #expect(themeManager.resolvedTheme == .darkBlue)
    }

    // MARK: - Design Tokens Reflect Theme + Accent

    @Test
    func designTokensReflectThemeAndAccentChanges() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.tokens-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        // Set dark purple + orange accent
        prefs.setThemeMode(.darkPurple)
        prefs.setAccentColor(.orange)

        let tokens = DesignTokens.tokens(
            for: themeManager.resolvedTheme,
            accent: themeManager.accentColor,
        )

        // Accent should be orange
        #expect(tokens.colors.accent == AccentColor.orange.color)
        #expect(tokens.colors.accentHover == AccentColor.orange.hoverColor)
        #expect(tokens.colors.accentPressed == AccentColor.orange.pressedColor)

        // Now switch to dark blue + cyan
        prefs.setThemeMode(.darkBlue)
        prefs.setAccentColor(.cyan)

        let tokens2 = DesignTokens.tokens(
            for: themeManager.resolvedTheme,
            accent: themeManager.accentColor,
        )

        // Background should differ (different theme)
        #expect(
            tokens.colors.background != tokens2.colors.background,
            "DarkPurple and DarkBlue should have different backgrounds",
        )

        // Accent should be cyan now
        #expect(tokens2.colors.accent == AccentColor.cyan.color)
    }

    // MARK: - Legacy Migration

    @Test
    func legacyDarkThemeMigratesToDarkBlue() throws {
        let suiteName = "com.unmissable.e2e.migrate-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))

        // Simulate old stored value
        testDefaults.set("dark", forKey: "appearanceTheme")

        let themeManager = ThemeManager()
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        #expect(
            prefs.themeMode == .darkBlue,
            "Legacy 'dark' should migrate to 'darkBlue'",
        )
        #expect(themeManager.resolvedTheme == .darkBlue)

        // Verify new key was written
        #expect(testDefaults.string(forKey: "themeMode") == "darkBlue")
    }

    @Test
    func legacyLightThemeMigratesToLight() throws {
        let suiteName = "com.unmissable.e2e.migrate-light-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        testDefaults.set("light", forKey: "appearanceTheme")

        let themeManager = ThemeManager()
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        #expect(prefs.themeMode == .light)
        #expect(themeManager.resolvedTheme == .light)
    }

    @Test
    func legacySystemThemeMigratesToSystem() throws {
        let suiteName = "com.unmissable.e2e.migrate-system-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        testDefaults.set("system", forKey: "appearanceTheme")

        let themeManager = ThemeManager()
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        #expect(prefs.themeMode == .system)
    }

    // MARK: - Accent + Theme Independence

    @Test
    func accentColorIsIndependentOfThemeMode() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.independence-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        prefs.setAccentColor(.red)
        prefs.setThemeMode(.darkBrown)

        #expect(themeManager.accentColor == .red)
        #expect(themeManager.resolvedTheme == .darkBrown)

        // Changing theme should not affect accent
        prefs.setThemeMode(.light)
        #expect(
            themeManager.accentColor == .red,
            "Accent should not change when theme mode changes",
        )

        // Changing accent should not affect theme
        prefs.setAccentColor(.violet)
        #expect(
            themeManager.resolvedTheme == .light,
            "Theme should not change when accent changes",
        )
    }

    // MARK: - Full Cycle: All Theme × Accent Combinations

    @Test
    func allThemeAccentCombinationsProduceValidTokens() {
        let darkThemes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        let accents = AccentColor.allCases

        for theme in darkThemes {
            for accent in accents {
                let tokens = DesignTokens.tokens(for: theme, accent: accent)

                // Every combination must produce non-equal bg vs text
                #expect(
                    tokens.colors.background != tokens.colors.textPrimary,
                    "Theme \(theme) + accent \(accent): bg must differ from text",
                )

                // Accent must match the input accent
                #expect(
                    tokens.colors.accent == accent.color,
                    "Theme \(theme) + accent \(accent): accent color must match",
                )
            }
        }
    }

    // MARK: - Bindings

    @Test
    func themeModeBindingUpdatesThemeManager() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.binding-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        // Simulate SwiftUI binding set
        prefs.themeModeBinding.wrappedValue = .darkBlack
        #expect(prefs.themeMode == .darkBlack)
        #expect(themeManager.resolvedTheme == .darkBlack)
    }

    @Test
    func accentColorBindingUpdatesThemeManager() throws {
        let themeManager = ThemeManager()
        let suiteName = "com.unmissable.e2e.accent-binding-\(UUID().uuidString)"

        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        let prefs = PreferencesManager(userDefaults: testDefaults, themeManager: themeManager)

        prefs.accentColorBinding.wrappedValue = .green
        #expect(prefs.accentColor == .green)
        #expect(themeManager.accentColor == .green)
    }
}
