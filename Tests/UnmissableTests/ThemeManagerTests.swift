@testable import Unmissable
import XCTest

@MainActor
final class ThemeManagerTests: XCTestCase {
    // MARK: - Default State

    func testDefaultThemeIsSystem() {
        let manager = ThemeManager()
        XCTAssertEqual(manager.currentTheme, .system)
    }

    func testDefaultEffectiveThemeIsDarkInTestEnvironment() {
        // In SPM test bundles, NSApp is nil, so system → dark fallback
        let manager = ThemeManager()
        XCTAssertEqual(manager.effectiveTheme, .dark)
    }

    // MARK: - setTheme

    func testSetThemeLightChangesEffectiveTheme() {
        let manager = ThemeManager()
        manager.setTheme(.light)

        XCTAssertEqual(manager.currentTheme, .light)
        XCTAssertEqual(manager.effectiveTheme, .light)
    }

    func testSetThemeDarkChangesEffectiveTheme() {
        let manager = ThemeManager()
        manager.setTheme(.dark)

        XCTAssertEqual(manager.currentTheme, .dark)
        XCTAssertEqual(manager.effectiveTheme, .dark)
    }

    func testSetThemeSystemFallsToDarkWithoutNSApp() {
        let manager = ThemeManager()
        manager.setTheme(.light) // change to something else first
        manager.setTheme(.system)

        XCTAssertEqual(manager.currentTheme, .system)
        // Without NSApp, system resolves to dark
        XCTAssertEqual(manager.effectiveTheme, .dark)
    }

    func testThemeTransitionsDoNotCrash() {
        let manager = ThemeManager()
        // Cycle through all themes rapidly
        for theme in AppTheme.allCases {
            manager.setTheme(theme)
        }
        // Reverse
        for theme in AppTheme.allCases.reversed() {
            manager.setTheme(theme)
        }
        // Manager should be in a consistent state
        XCTAssertEqual(manager.currentTheme, .system)
    }

    // MARK: - CustomDesign

    func testDesignForLightHasLightColors() {
        let design = CustomDesign.design(for: .light)
        // Light theme has dark text on light background
        // The background should be near-white (#FAFAFA)
        // We verify the design object is structurally correct by checking non-nil access
        XCTAssertNotEqual(design.colors.background, design.colors.textPrimary)
    }

    func testDesignForDarkHasDarkColors() {
        let design = CustomDesign.design(for: .dark)
        // Dark theme has light text on dark background
        XCTAssertNotEqual(design.colors.background, design.colors.textPrimary)
    }

    func testDesignForDifferentThemesProducesDifferentColors() {
        let lightDesign = CustomDesign.design(for: .light)
        let darkDesign = CustomDesign.design(for: .dark)

        // Light background should differ from dark background
        XCTAssertNotEqual(
            lightDesign.colors.background,
            darkDesign.colors.background,
            "Light and dark themes should have different background colors"
        )
    }

    // MARK: - AppTheme Properties

    func testAppThemeDisplayNames() {
        XCTAssertEqual(AppTheme.system.displayName, "Follow System")
        XCTAssertEqual(AppTheme.light.displayName, "Light")
        XCTAssertEqual(AppTheme.dark.displayName, "Dark")
    }

    func testAppThemeCaseIterable() {
        XCTAssertEqual(AppTheme.allCases.count, 3)
    }

    func testAppThemeRawValues() {
        XCTAssertEqual(AppTheme.system.rawValue, "system")
        XCTAssertEqual(AppTheme.light.rawValue, "light")
        XCTAssertEqual(AppTheme.dark.rawValue, "dark")
    }
}
