import Foundation
import SwiftUI
import Testing
@testable import Unmissable

@MainActor
struct ThemeManagerTests {
    // MARK: - Default State

    @Test
    func defaultThemeIsSystem() {
        let manager = ThemeManager()
        #expect(manager.themeMode == .system)
    }

    @Test
    func defaultResolvedThemeIsDarkBlueInTestEnvironment() {
        // In SPM test bundles, NSApp is nil, so system -> darkBlue fallback
        let manager = ThemeManager()
        #expect(manager.resolvedTheme == .darkBlue)
    }

    // MARK: - setTheme

    @Test
    func setThemeLightChangesResolvedTheme() {
        let manager = ThemeManager()
        manager.setTheme(.light)

        #expect(manager.themeMode == .light)
        #expect(manager.resolvedTheme == .light)
    }

    @Test
    func setThemeDarkBlueChangesResolvedTheme() {
        let manager = ThemeManager()
        manager.setTheme(.darkBlue)

        #expect(manager.themeMode == .darkBlue)
        #expect(manager.resolvedTheme == .darkBlue)
    }

    @Test
    func setThemeSystemFallsToDarkBlueWithoutNSApp() {
        let manager = ThemeManager()
        manager.setTheme(.light) // change to something else first
        manager.setTheme(.system)

        #expect(manager.themeMode == .system)
        // Without NSApp, system resolves to darkBlue
        #expect(manager.resolvedTheme == .darkBlue)
    }

    @Test
    func themeTransitionsDoNotCrash() {
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
        #expect(manager.themeMode == .system)
    }

    // MARK: - DesignTokens

    @Test
    func designForLightHasLightColors() {
        let design = DesignTokens.tokens(for: .light, accent: .blue)
        // Light theme has dark text on light background
        // The background should be near-white (#FAFAFA)
        // We verify the design object is structurally correct by checking non-nil access
        #expect(design.colors.background != design.colors.textPrimary)
    }

    @Test
    func designForDarkHasDarkColors() {
        let design = DesignTokens.tokens(for: .darkBlue, accent: .blue)
        // Dark theme has light text on dark background
        #expect(design.colors.background != design.colors.textPrimary)
    }

    @Test
    func designForDifferentThemesProducesDifferentColors() {
        let lightDesign = DesignTokens.tokens(for: .light, accent: .blue)
        let darkDesign = DesignTokens.tokens(for: .darkBlue, accent: .blue)

        // Light background should differ from dark background
        #expect(
            lightDesign.colors.background != darkDesign.colors.background,
            "Light and dark themes should have different background colors",
        )
    }

    // MARK: - ThemeMode Properties

    @Test
    func themeModeDisplayNames() {
        #expect(ThemeMode.system.displayName == "System")
        #expect(ThemeMode.light.displayName == "Light")
        #expect(ThemeMode.darkBlue.displayName == "Dark Blue")
    }

    @Test
    func themeModeCaseIterable() {
        #expect(
            ThemeMode.allCases == [.system, .light, .darkBlue, .darkPurple, .darkBrown, .darkBlack],
        )
    }

    @Test
    func themeModeRawValues() {
        #expect(ThemeMode.system.rawValue == "system")
        #expect(ThemeMode.light.rawValue == "light")
        #expect(ThemeMode.darkBlue.rawValue == "darkBlue")
        #expect(ThemeMode.darkPurple.rawValue == "darkPurple")
        #expect(ThemeMode.darkBrown.rawValue == "darkBrown")
        #expect(ThemeMode.darkBlack.rawValue == "darkBlack")
    }

    // MARK: - Accent Color

    @Test
    func setAccentChangesAccentColor() {
        let manager = ThemeManager()
        manager.setAccent(.orange)
        #expect(manager.accentColor == .orange)
    }

    // MARK: - Design Token System: Theme Distinctness

    @Test
    func allFiveResolvedThemesProduceDistinctBackgrounds() {
        let themes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        let backgrounds = themes.map {
            DesignTokens.tokens(for: $0, accent: .blue).colors.background
        }

        for i in 0 ..< backgrounds.count {
            for j in (i + 1) ..< backgrounds.count {
                #expect(
                    backgrounds[i] != backgrounds[j],
                    "\(themes[i]) and \(themes[j]) should have distinct background colors",
                )
            }
        }
    }

    // MARK: - Design Token System: Accent Color Distinctness

    @Test
    func allSevenAccentColorsProduceDistinctValues() {
        let accents = AccentColor.allCases
        #expect(
            accents == [.blue, .cyan, .green, .magenta, .orange, .violet, .red],
        )

        for i in 0 ..< accents.count {
            for j in (i + 1) ..< accents.count {
                #expect(
                    accents[i].color != accents[j].color,
                    "\(accents[i].rawValue) and \(accents[j].rawValue) should have distinct accent colors",
                )
            }
        }
    }

    // MARK: - Design Token System: Accent Hover/Pressed Differ From Base

    @Test
    func accentHoverAndPressedDifferFromBase() {
        for accent in AccentColor.allCases {
            #expect(
                accent.color != accent.hoverColor,
                "\(accent.rawValue): hover should differ from base",
            )
            #expect(
                accent.color != accent.pressedColor,
                "\(accent.rawValue): pressed should differ from base",
            )
            #expect(
                accent.hoverColor != accent.pressedColor,
                "\(accent.rawValue): hover should differ from pressed",
            )
        }
    }

    // MARK: - Design Token System: Accent Subtle Differs From Accent

    @Test
    func accentSubtleDiffersFromAccent() {
        // accentSubtle applies 0.15 opacity to the accent color, so it must differ
        for accent in AccentColor.allCases {
            let tokens = DesignTokens.tokens(for: .darkBlue, accent: accent)
            #expect(
                tokens.colors.accent != tokens.colors.accentSubtle,
                "\(accent.rawValue): accentSubtle (0.15 opacity) should differ from accent",
            )
        }
    }

    // MARK: - Design Token System: Theme Mode Dark Detection

    @Test
    func resolvedThemeIsDarkDetection() {
        #expect(
            !ResolvedTheme.light.isDark,
            "Light theme should not be dark",
        )
        let darkThemes: [ResolvedTheme] = [.darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in darkThemes {
            #expect(
                theme.isDark,
                "\(theme.rawValue) should be detected as dark",
            )
        }
    }

    // MARK: - Design Token System: Dark Themes Have Status Colors

    @Test
    func allDarkThemesHaveNonClearStatusColors() {
        let darkThemes: [ResolvedTheme] = [.darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in darkThemes {
            let colors = DesignTokens.tokens(for: theme, accent: .blue).colors

            #expect(
                colors.success != Color.clear,
                "\(theme.rawValue): success should be non-clear",
            )
            #expect(
                colors.warning != Color.clear,
                "\(theme.rawValue): warning should be non-clear",
            )
            #expect(
                colors.error != Color.clear,
                "\(theme.rawValue): error should be non-clear",
            )
            #expect(
                colors.successSubtle != Color.clear,
                "\(theme.rawValue): successSubtle should be non-clear",
            )
            #expect(
                colors.warningSubtle != Color.clear,
                "\(theme.rawValue): warningSubtle should be non-clear",
            )
            #expect(
                colors.errorSubtle != Color.clear,
                "\(theme.rawValue): errorSubtle should be non-clear",
            )
        }
    }

    // MARK: - Design Token System: Surface Hierarchy

    @Test
    func eachThemeHasDistinctSurfaceHierarchy() {
        let allThemes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in allThemes {
            let colors = DesignTokens.tokens(for: theme, accent: .blue).colors

            #expect(
                colors.background != colors.panel,
                "\(theme.rawValue): background and panel should be distinct layers",
            )
            #expect(
                colors.background != colors.surface,
                "\(theme.rawValue): background and surface should be distinct layers",
            )
            #expect(
                colors.panel != colors.surface,
                "\(theme.rawValue): panel and surface should be distinct layers",
            )
        }
    }

    // MARK: - Design Token System: AccentColor Display Names

    @Test
    func accentColorDisplayNameMatchesCapitalizedRawValue() {
        for accent in AccentColor.allCases {
            #expect(
                accent.displayName == accent.rawValue.capitalized,
                "\(accent.rawValue): displayName should equal capitalized rawValue",
            )
        }
    }

    // MARK: - Design Token System: Spacing Constants

    @Test
    func designSpacingStandardValues() {
        let spacing = DesignSpacing.standard
        #expect(spacing.xs == 4, "xs should be 4")
        #expect(spacing.sm == 8, "sm should be 8")
        #expect(spacing.md == 12, "md should be 12")
        #expect(spacing.lg == 16, "lg should be 16")
        #expect(spacing.xl == 20, "xl should be 20")
        #expect(spacing.xxl == 24, "xxl should be 24")
        #expect(spacing.xxxl == 32, "xxxl should be 32")
    }

    // MARK: - Design Token System: Corner Radius Constants

    @Test
    func designCornersStandardValues() {
        let corners = DesignCorners.standard
        #expect(corners.sm == 6, "sm should be 6")
        #expect(corners.md == 8, "md should be 8")
        #expect(corners.lg == 12, "lg should be 12")
        #expect(corners.xl == 16, "xl should be 16")
        #expect(corners.full == 999, "full should be 999")
    }

    // MARK: - Design Token System: Tracking Constants

    @Test
    func designTrackingConstants() {
        #expect(DesignTracking.sectionLabel == 1.5, "sectionLabel tracking should be 1.5")
        #expect(DesignTracking.tight == -0.2, "tight tracking should be -0.2")
        #expect(DesignTracking.normal == 0.0, "normal tracking should be 0.0")
        #expect(DesignTracking.wide == 0.5, "wide tracking should be 0.5")
        #expect(DesignTracking.wider == 1.0, "wider tracking should be 1.0")
        #expect(DesignTracking.header == 0.8, "header tracking should be 0.8")
    }

    // MARK: - Design Token System: Shadow Radii

    @Test
    func designShadowsPerThemeAreNonZero() {
        let allThemes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in allThemes {
            let shadows = DesignShadows.shadows(for: theme)
            #expect(
                shadows.soft.radius >= 4,
                "\(theme.rawValue): soft shadow radius should be >= 4",
            )
            #expect(
                shadows.hard.radius >= 1,
                "\(theme.rawValue): hard shadow radius should be >= 1",
            )
        }
    }

    // MARK: - Design Token System: Accent Independent of Theme

    @Test
    func accentColorInjectedIndependentlyFromTheme() {
        let darkBlueTokens = DesignTokens.tokens(for: .darkBlue, accent: .orange)
        let darkPurpleTokens = DesignTokens.tokens(for: .darkPurple, accent: .orange)

        // Same accent -> identical accent colors
        #expect(
            darkBlueTokens.colors.accent == darkPurpleTokens.colors.accent,
            "Same AccentColor should produce identical accent regardless of theme",
        )
        #expect(
            darkBlueTokens.colors.accentHover == darkPurpleTokens.colors.accentHover,
            "Same AccentColor should produce identical accentHover regardless of theme",
        )
        #expect(
            darkBlueTokens.colors.accentPressed == darkPurpleTokens.colors.accentPressed,
            "Same AccentColor should produce identical accentPressed regardless of theme",
        )

        // Different themes -> different backgrounds
        #expect(
            darkBlueTokens.colors.background != darkPurpleTokens.colors.background,
            "Different themes should still produce different backgrounds",
        )
    }

    // MARK: - Design Token System: ThemeManager Dark Mode Variants

    @Test
    func setThemeForAllDarkModes() {
        let manager = ThemeManager()

        manager.setTheme(.darkPurple)
        #expect(
            manager.resolvedTheme == .darkPurple,
            "setTheme(.darkPurple) should resolve to .darkPurple",
        )

        manager.setTheme(.darkBrown)
        #expect(
            manager.resolvedTheme == .darkBrown,
            "setTheme(.darkBrown) should resolve to .darkBrown",
        )

        manager.setTheme(.darkBlack)
        #expect(
            manager.resolvedTheme == .darkBlack,
            "setTheme(.darkBlack) should resolve to .darkBlack",
        )
    }

    // MARK: - Design Token System: ThemeManager Default Accent

    @Test
    func themeManagerDefaultAccentIsBlue() {
        let manager = ThemeManager()
        #expect(manager.accentColor == .blue, "Default accent color should be blue")
    }
}
