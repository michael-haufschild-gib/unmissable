import SwiftUI
@testable import Unmissable
import XCTest

@MainActor
final class ThemeManagerTests: XCTestCase {
    // MARK: - Default State

    func testDefaultThemeIsSystem() {
        let manager = ThemeManager()
        XCTAssertEqual(manager.themeMode, .system)
    }

    func testDefaultResolvedThemeIsDarkBlueInTestEnvironment() {
        // In SPM test bundles, NSApp is nil, so system -> darkBlue fallback
        let manager = ThemeManager()
        XCTAssertEqual(manager.resolvedTheme, .darkBlue)
    }

    // MARK: - setTheme

    func testSetThemeLightChangesResolvedTheme() {
        let manager = ThemeManager()
        manager.setTheme(.light)

        XCTAssertEqual(manager.themeMode, .light)
        XCTAssertEqual(manager.resolvedTheme, .light)
    }

    func testSetThemeDarkBlueChangesResolvedTheme() {
        let manager = ThemeManager()
        manager.setTheme(.darkBlue)

        XCTAssertEqual(manager.themeMode, .darkBlue)
        XCTAssertEqual(manager.resolvedTheme, .darkBlue)
    }

    func testSetThemeSystemFallsToDarkBlueWithoutNSApp() {
        let manager = ThemeManager()
        manager.setTheme(.light) // change to something else first
        manager.setTheme(.system)

        XCTAssertEqual(manager.themeMode, .system)
        // Without NSApp, system resolves to darkBlue
        XCTAssertEqual(manager.resolvedTheme, .darkBlue)
    }

    func testThemeTransitionsDoNotCrash() {
        let manager = ThemeManager()
        // Cycle through all themes rapidly
        for theme in ThemeMode.allCases {
            manager.setTheme(theme)
        }
        // Reverse
        for theme in ThemeMode.allCases.reversed() {
            manager.setTheme(theme)
        }
        // Manager should be in a consistent state
        XCTAssertEqual(manager.themeMode, .system)
    }

    // MARK: - DesignTokens

    func testDesignForLightHasLightColors() {
        let design = DesignTokens.tokens(for: .light, accent: .blue)
        // Light theme has dark text on light background
        // The background should be near-white (#FAFAFA)
        // We verify the design object is structurally correct by checking non-nil access
        XCTAssertNotEqual(design.colors.background, design.colors.textPrimary)
    }

    func testDesignForDarkHasDarkColors() {
        let design = DesignTokens.tokens(for: .darkBlue, accent: .blue)
        // Dark theme has light text on dark background
        XCTAssertNotEqual(design.colors.background, design.colors.textPrimary)
    }

    func testDesignForDifferentThemesProducesDifferentColors() {
        let lightDesign = DesignTokens.tokens(for: .light, accent: .blue)
        let darkDesign = DesignTokens.tokens(for: .darkBlue, accent: .blue)

        // Light background should differ from dark background
        XCTAssertNotEqual(
            lightDesign.colors.background,
            darkDesign.colors.background,
            "Light and dark themes should have different background colors",
        )
    }

    // MARK: - ThemeMode Properties

    func testThemeModeDisplayNames() {
        XCTAssertEqual(ThemeMode.system.displayName, "System")
        XCTAssertEqual(ThemeMode.light.displayName, "Light")
        XCTAssertEqual(ThemeMode.darkBlue.displayName, "Dark Blue")
    }

    func testThemeModeCaseIterable() {
        XCTAssertEqual(
            ThemeMode.allCases,
            [.system, .light, .darkBlue, .darkPurple, .darkBrown, .darkBlack],
        )
    }

    func testThemeModeRawValues() {
        XCTAssertEqual(ThemeMode.system.rawValue, "system")
        XCTAssertEqual(ThemeMode.light.rawValue, "light")
        XCTAssertEqual(ThemeMode.darkBlue.rawValue, "darkBlue")
        XCTAssertEqual(ThemeMode.darkPurple.rawValue, "darkPurple")
        XCTAssertEqual(ThemeMode.darkBrown.rawValue, "darkBrown")
        XCTAssertEqual(ThemeMode.darkBlack.rawValue, "darkBlack")
    }

    // MARK: - Accent Color

    func testSetAccentChangesAccentColor() {
        let manager = ThemeManager()
        manager.setAccent(.orange)
        XCTAssertEqual(manager.accentColor, .orange)
    }

    // MARK: - Design Token System: Theme Distinctness

    func testAllFiveResolvedThemesProduceDistinctBackgrounds() {
        let themes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        let backgrounds = themes.map {
            DesignTokens.tokens(for: $0, accent: .blue).colors.background
        }

        for i in 0 ..< backgrounds.count {
            for j in (i + 1) ..< backgrounds.count {
                XCTAssertNotEqual(
                    backgrounds[i],
                    backgrounds[j],
                    "\(themes[i]) and \(themes[j]) should have distinct background colors",
                )
            }
        }
    }

    // MARK: - Design Token System: Accent Color Distinctness

    func testAllSevenAccentColorsProduceDistinctValues() {
        let accents = AccentColor.allCases
        XCTAssertEqual(
            accents,
            [.blue, .cyan, .green, .magenta, .orange, .violet, .red],
        )

        for i in 0 ..< accents.count {
            for j in (i + 1) ..< accents.count {
                XCTAssertNotEqual(
                    accents[i].color,
                    accents[j].color,
                    "\(accents[i].rawValue) and \(accents[j].rawValue) should have distinct accent colors",
                )
            }
        }
    }

    // MARK: - Design Token System: Accent Hover/Pressed Differ From Base

    func testAccentHoverAndPressedDifferFromBase() {
        for accent in AccentColor.allCases {
            XCTAssertNotEqual(
                accent.color,
                accent.hoverColor,
                "\(accent.rawValue): hover should differ from base",
            )
            XCTAssertNotEqual(
                accent.color,
                accent.pressedColor,
                "\(accent.rawValue): pressed should differ from base",
            )
            XCTAssertNotEqual(
                accent.hoverColor,
                accent.pressedColor,
                "\(accent.rawValue): hover should differ from pressed",
            )
        }
    }

    // MARK: - Design Token System: Accent Subtle Differs From Accent

    func testAccentSubtleDiffersFromAccent() {
        // accentSubtle applies 0.15 opacity to the accent color, so it must differ
        for accent in AccentColor.allCases {
            let tokens = DesignTokens.tokens(for: .darkBlue, accent: accent)
            XCTAssertNotEqual(
                tokens.colors.accent,
                tokens.colors.accentSubtle,
                "\(accent.rawValue): accentSubtle (0.15 opacity) should differ from accent",
            )
        }
    }

    // MARK: - Design Token System: Theme Mode Dark Detection

    func testResolvedThemeIsDarkDetection() {
        XCTAssertFalse(
            ResolvedTheme.light.isDark,
            "Light theme should not be dark",
        )
        let darkThemes: [ResolvedTheme] = [.darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in darkThemes {
            XCTAssertTrue(
                theme.isDark,
                "\(theme.rawValue) should be detected as dark",
            )
        }
    }

    // MARK: - Design Token System: Dark Themes Have Status Colors

    func testAllDarkThemesHaveNonClearStatusColors() {
        let darkThemes: [ResolvedTheme] = [.darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in darkThemes {
            let colors = DesignTokens.tokens(for: theme, accent: .blue).colors

            XCTAssertNotEqual(
                colors.success,
                Color.clear,
                "\(theme.rawValue): success should be non-clear",
            )
            XCTAssertNotEqual(
                colors.warning,
                Color.clear,
                "\(theme.rawValue): warning should be non-clear",
            )
            XCTAssertNotEqual(
                colors.error,
                Color.clear,
                "\(theme.rawValue): error should be non-clear",
            )
            XCTAssertNotEqual(
                colors.successSubtle,
                Color.clear,
                "\(theme.rawValue): successSubtle should be non-clear",
            )
            XCTAssertNotEqual(
                colors.warningSubtle,
                Color.clear,
                "\(theme.rawValue): warningSubtle should be non-clear",
            )
            XCTAssertNotEqual(
                colors.errorSubtle,
                Color.clear,
                "\(theme.rawValue): errorSubtle should be non-clear",
            )
        }
    }

    // MARK: - Design Token System: Surface Hierarchy

    func testEachThemeHasDistinctSurfaceHierarchy() {
        let allThemes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in allThemes {
            let colors = DesignTokens.tokens(for: theme, accent: .blue).colors

            XCTAssertNotEqual(
                colors.background,
                colors.panel,
                "\(theme.rawValue): background and panel should be distinct layers",
            )
            XCTAssertNotEqual(
                colors.background,
                colors.surface,
                "\(theme.rawValue): background and surface should be distinct layers",
            )
            XCTAssertNotEqual(
                colors.panel,
                colors.surface,
                "\(theme.rawValue): panel and surface should be distinct layers",
            )
        }
    }

    // MARK: - Design Token System: AccentColor Display Names

    func testAccentColorDisplayNameMatchesCapitalizedRawValue() {
        for accent in AccentColor.allCases {
            XCTAssertEqual(
                accent.displayName,
                accent.rawValue.capitalized,
                "\(accent.rawValue): displayName should equal capitalized rawValue",
            )
        }
    }

    // MARK: - Design Token System: Spacing Constants

    func testDesignSpacingStandardValues() {
        let spacing = DesignSpacing.standard
        XCTAssertEqual(spacing.xs, 4, "xs should be 4")
        XCTAssertEqual(spacing.sm, 8, "sm should be 8")
        XCTAssertEqual(spacing.md, 12, "md should be 12")
        XCTAssertEqual(spacing.lg, 16, "lg should be 16")
        XCTAssertEqual(spacing.xl, 20, "xl should be 20")
        XCTAssertEqual(spacing.xxl, 24, "xxl should be 24")
        XCTAssertEqual(spacing.xxxl, 32, "xxxl should be 32")
    }

    // MARK: - Design Token System: Corner Radius Constants

    func testDesignCornersStandardValues() {
        let corners = DesignCorners.standard
        XCTAssertEqual(corners.sm, 6, "sm should be 6")
        XCTAssertEqual(corners.md, 8, "md should be 8")
        XCTAssertEqual(corners.lg, 12, "lg should be 12")
        XCTAssertEqual(corners.xl, 16, "xl should be 16")
        XCTAssertEqual(corners.full, 999, "full should be 999")
    }

    // MARK: - Design Token System: Tracking Constants

    func testDesignTrackingConstants() {
        XCTAssertEqual(DesignTracking.sectionLabel, 1.5, "sectionLabel tracking should be 1.5")
        XCTAssertEqual(DesignTracking.tight, -0.2, "tight tracking should be -0.2")
        XCTAssertEqual(DesignTracking.normal, 0.0, "normal tracking should be 0.0")
        XCTAssertEqual(DesignTracking.wide, 0.5, "wide tracking should be 0.5")
        XCTAssertEqual(DesignTracking.wider, 1.0, "wider tracking should be 1.0")
        XCTAssertEqual(DesignTracking.header, 0.8, "header tracking should be 0.8")
    }

    // MARK: - Design Token System: Shadow Radii

    func testDesignShadowsPerThemeAreNonZero() {
        let allThemes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in allThemes {
            let shadows = DesignShadows.shadows(for: theme)
            XCTAssertGreaterThanOrEqual(
                shadows.soft.radius,
                4,
                "\(theme.rawValue): soft shadow radius should be >= 4",
            )
            XCTAssertGreaterThanOrEqual(
                shadows.hard.radius,
                1,
                "\(theme.rawValue): hard shadow radius should be >= 1",
            )
        }
    }

    // MARK: - Design Token System: Accent Independent of Theme

    func testAccentColorInjectedIndependentlyFromTheme() {
        let darkBlueTokens = DesignTokens.tokens(for: .darkBlue, accent: .orange)
        let darkPurpleTokens = DesignTokens.tokens(for: .darkPurple, accent: .orange)

        // Same accent -> identical accent colors
        XCTAssertEqual(
            darkBlueTokens.colors.accent,
            darkPurpleTokens.colors.accent,
            "Same AccentColor should produce identical accent regardless of theme",
        )
        XCTAssertEqual(
            darkBlueTokens.colors.accentHover,
            darkPurpleTokens.colors.accentHover,
            "Same AccentColor should produce identical accentHover regardless of theme",
        )
        XCTAssertEqual(
            darkBlueTokens.colors.accentPressed,
            darkPurpleTokens.colors.accentPressed,
            "Same AccentColor should produce identical accentPressed regardless of theme",
        )

        // Different themes -> different backgrounds
        XCTAssertNotEqual(
            darkBlueTokens.colors.background,
            darkPurpleTokens.colors.background,
            "Different themes should still produce different backgrounds",
        )
    }

    // MARK: - Design Token System: ThemeManager Dark Mode Variants

    func testSetThemeForAllDarkModes() {
        let manager = ThemeManager()

        manager.setTheme(.darkPurple)
        XCTAssertEqual(
            manager.resolvedTheme,
            .darkPurple,
            "setTheme(.darkPurple) should resolve to .darkPurple",
        )

        manager.setTheme(.darkBrown)
        XCTAssertEqual(
            manager.resolvedTheme,
            .darkBrown,
            "setTheme(.darkBrown) should resolve to .darkBrown",
        )

        manager.setTheme(.darkBlack)
        XCTAssertEqual(
            manager.resolvedTheme,
            .darkBlack,
            "setTheme(.darkBlack) should resolve to .darkBlack",
        )
    }

    // MARK: - Design Token System: ThemeManager Default Accent

    func testThemeManagerDefaultAccentIsBlue() {
        let manager = ThemeManager()
        XCTAssertEqual(manager.accentColor, .blue, "Default accent color should be blue")
    }
}
