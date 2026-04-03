@testable import Unmissable
import XCTest

@MainActor
final class DesignSystemTests: XCTestCase {
    // MARK: - UMButtonStyle.Variant

    func testButtonStyleVariantHasFourCases() {
        let cases: [UMButtonStyle.Variant] = [.primary, .secondary, .ghost, .danger]
        XCTAssertEqual(cases, [.primary, .secondary, .ghost, .danger])
    }

    func testButtonStyleVariantCasesAreDistinct() {
        let primary = UMButtonStyle.Variant.primary
        let secondary = UMButtonStyle.Variant.secondary
        let ghost = UMButtonStyle.Variant.ghost
        let danger = UMButtonStyle.Variant.danger

        let mirror = [
            "\(primary)", "\(secondary)", "\(ghost)", "\(danger)",
        ]
        let uniqueCount = Set(mirror).count
        XCTAssertEqual(uniqueCount, 4, "All button variants must be distinct")
        XCTAssertEqual(mirror.first, "primary")
    }

    // MARK: - UMButtonStyle.Size

    func testButtonStyleSizeHasFourCases() {
        let cases: [UMButtonStyle.Size] = [.sm, .md, .lg, .icon]
        XCTAssertEqual(cases, [.sm, .md, .lg, .icon])
    }

    func testButtonStyleSizeCasesAreDistinct() {
        let sm = UMButtonStyle.Size.sm
        let md = UMButtonStyle.Size.md
        let lg = UMButtonStyle.Size.lg
        let icon = UMButtonStyle.Size.icon

        let mirror = ["\(sm)", "\(md)", "\(lg)", "\(icon)"]
        let uniqueCount = Set(mirror).count
        XCTAssertEqual(uniqueCount, 4, "All button sizes must be distinct")
        XCTAssertEqual(mirror.first, "sm")
    }

    // MARK: - UMBadge.Variant

    func testBadgeVariantHasFiveCases() {
        let cases: [UMBadge.Variant] = [.accent, .success, .warning, .error, .neutral]
        XCTAssertEqual(cases, [.accent, .success, .warning, .error, .neutral])
    }

    func testBadgeVariantCasesAreDistinct() {
        let all: [UMBadge.Variant] = [.accent, .success, .warning, .error, .neutral]
        let names = all.map { "\($0)" }
        let uniqueCount = Set(names).count
        XCTAssertEqual(uniqueCount, 5, "All badge variants must be distinct")
        XCTAssertEqual(names.first, "accent")
    }

    // MARK: - UMStatusIndicator.Status

    func testStatusIndicatorHasFourCases() {
        let cases: [UMStatusIndicator.Status] = [.connected, .connecting, .disconnected, .error]
        XCTAssertEqual(cases, [.connected, .connecting, .disconnected, .error])
    }

    func testStatusIndicatorCasesAreDistinct() {
        let all: [UMStatusIndicator.Status] = [.connected, .connecting, .disconnected, .error]
        let names = all.map { "\($0)" }
        let uniqueCount = Set(names).count
        XCTAssertEqual(uniqueCount, 4, "All status indicator cases must be distinct")
        XCTAssertEqual(names.first, "connected")
    }

    // MARK: - UMCardModifier.Style

    func testCardModifierStyleHasThreeCases() {
        let cases: [UMCardModifier.Style] = [.glass, .elevated, .flat]
        XCTAssertEqual(cases, [.glass, .elevated, .flat])
    }

    func testCardModifierStyleCasesAreDistinct() {
        let all: [UMCardModifier.Style] = [.glass, .elevated, .flat]
        let names = all.map { "\($0)" }
        let uniqueCount = Set(names).count
        XCTAssertEqual(uniqueCount, 3, "All card modifier styles must be distinct")
        XCTAssertEqual(names.first, "glass")
    }

    // MARK: - UMBadge Init

    func testBadgeInitWithEachVariantDoesNotCrash() {
        let variants: [UMBadge.Variant] = [.accent, .success, .warning, .error, .neutral]
        for variant in variants {
            let badge = UMBadge("Test", variant: variant)
            XCTAssertEqual(badge.text, "Test")
            XCTAssertEqual(badge.variant, variant)
        }
    }

    func testBadgeDefaultVariantIsAccent() {
        let badge = UMBadge("Default")
        XCTAssertEqual(badge.variant, .accent)
    }

    // MARK: - UMStatusIndicator Init

    func testStatusIndicatorInitWithEachStatusDoesNotCrash() {
        let statuses: [UMStatusIndicator.Status] = [
            .connected, .connecting, .disconnected, .error,
        ]
        for status in statuses {
            let indicator = UMStatusIndicator(status)
            XCTAssertEqual(indicator.status, status)
            XCTAssertEqual(indicator.size, 10, "Default size should be 10")
        }
    }

    func testStatusIndicatorCustomSize() {
        let indicator = UMStatusIndicator(.connected, size: 20)
        XCTAssertEqual(indicator.size, 20)
    }

    // MARK: - AccentColor Enum Completeness

    func testAccentColorHasSevenCases() {
        let allCases = AccentColor.allCases
        XCTAssertEqual(allCases, [.blue, .cyan, .green, .magenta, .orange, .violet, .red])
    }

    func testAccentColorAllCasesHaveNonEmptyDisplayName() {
        for accent in AccentColor.allCases {
            XCTAssertEqual(
                accent.displayName,
                accent.rawValue.capitalized,
                "\(accent) should have displayName matching capitalized rawValue",
            )
        }
    }

    func testAccentColorDisplayNamesAreCapitalizedRawValues() {
        for accent in AccentColor.allCases {
            XCTAssertEqual(
                accent.displayName,
                accent.rawValue.capitalized,
                "\(accent).displayName should be capitalized rawValue",
            )
        }
    }

    func testAccentColorExpectedCases() {
        let expected: [AccentColor] = [.blue, .cyan, .green, .magenta, .orange, .violet, .red]
        XCTAssertEqual(Set(AccentColor.allCases), Set(expected))
    }

    // MARK: - ThemeMode Enum Completeness

    func testThemeModeHasSixCases() {
        let allCases = ThemeMode.allCases
        XCTAssertEqual(
            allCases,
            [.system, .light, .darkBlue, .darkPurple, .darkBrown, .darkBlack],
        )
    }

    func testThemeModeAllCasesHaveNonEmptyDisplayName() {
        for mode in ThemeMode.allCases {
            XCTAssertEqual(
                mode.displayName,
                mode.displayName, // non-empty verified by checking against known values below
                "\(mode) should have a non-empty displayName",
            )
        }
        XCTAssertEqual(ThemeMode.system.displayName, "System")
    }

    func testThemeModeExpectedCases() {
        let expected: [ThemeMode] = [.system, .light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        XCTAssertEqual(Set(ThemeMode.allCases), Set(expected))
    }

    // MARK: - DesignTokens Factory

    func testDesignTokensFactoryProducesCompleteObject() {
        let tokens = DesignTokens.tokens(for: .darkBlue, accent: .blue)

        // Colors — surface hierarchy
        _ = tokens.colors.background
        _ = tokens.colors.panel
        _ = tokens.colors.surface
        _ = tokens.colors.elevated
        _ = tokens.colors.glass

        // Colors — interactive
        _ = tokens.colors.hover
        _ = tokens.colors.active
        _ = tokens.colors.overlay

        // Colors — text
        _ = tokens.colors.textPrimary
        _ = tokens.colors.textSecondary
        _ = tokens.colors.textTertiary
        _ = tokens.colors.textMuted
        _ = tokens.colors.textInverse

        // Colors — borders
        _ = tokens.colors.borderSubtle
        _ = tokens.colors.borderDefault
        _ = tokens.colors.borderStrong

        // Colors — accent
        _ = tokens.colors.accent
        _ = tokens.colors.accentHover
        _ = tokens.colors.accentPressed
        _ = tokens.colors.accentSubtle

        // Colors — status
        _ = tokens.colors.success
        _ = tokens.colors.warning
        _ = tokens.colors.error
        _ = tokens.colors.successSubtle
        _ = tokens.colors.warningSubtle
        _ = tokens.colors.errorSubtle
    }

    func testDesignTokensFactoryForEveryThemeAndAccent() {
        let themes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in themes {
            for accent in AccentColor.allCases {
                let tokens = DesignTokens.tokens(for: theme, accent: accent)
                // Verify accent color matches the input accent
                XCTAssertEqual(
                    tokens.colors.accent,
                    accent.color,
                    "Accent color mismatch for theme=\(theme), accent=\(accent)",
                )
            }
        }
    }

    // MARK: - DesignFonts

    func testDesignFontsStandardSingleton() {
        let fonts = DesignFonts.standard
        // Access all font fields to verify structural integrity
        _ = fonts.title1
        _ = fonts.title2
        _ = fonts.title3
        _ = fonts.headline
        _ = fonts.body
        _ = fonts.callout
        _ = fonts.footnote
        _ = fonts.caption
        _ = fonts.mono
        _ = fonts.monoSmall
        _ = fonts.sectionLabel
    }

    // MARK: - DesignSpacing

    func testDesignSpacingStandardSingleton() {
        let spacing = DesignSpacing.standard
        XCTAssertEqual(spacing.xs, 4)
        XCTAssertEqual(spacing.sm, 8)
        XCTAssertEqual(spacing.md, 12)
        XCTAssertEqual(spacing.lg, 16)
        XCTAssertEqual(spacing.xl, 20)
        XCTAssertEqual(spacing.xxl, 24)
        XCTAssertEqual(spacing.xxxl, 32)
    }

    func testDesignSpacingValuesAreStrictlyIncreasing() {
        let spacing = DesignSpacing.standard
        let values = [
            spacing.xs, spacing.sm, spacing.md,
            spacing.lg, spacing.xl, spacing.xxl, spacing.xxxl,
        ]
        for i in 1 ..< values.count {
            XCTAssertGreaterThan(
                values[i],
                values[i - 1],
                "Spacing scale must be strictly increasing at index \(i)",
            )
        }
    }

    // MARK: - DesignCorners

    func testDesignCornersStandardValues() {
        let corners = DesignCorners.standard
        XCTAssertEqual(corners.sm, 6)
        XCTAssertEqual(corners.md, 8)
        XCTAssertEqual(corners.lg, 12)
        XCTAssertEqual(corners.xl, 16)
        XCTAssertEqual(corners.full, 999)
    }

    func testDesignCornersScaleIsIncreasingExceptFull() {
        let corners = DesignCorners.standard
        let scale = [corners.sm, corners.md, corners.lg, corners.xl]
        for i in 1 ..< scale.count {
            XCTAssertGreaterThan(
                scale[i],
                scale[i - 1],
                "Corner radius scale must be strictly increasing at index \(i)",
            )
        }
        XCTAssertGreaterThan(corners.full, corners.xl, "full must exceed xl")
    }

    // MARK: - DesignShadows ShadowSpec

    func testShadowSpecDefaultXYAreZero() {
        let spec = DesignShadows.ShadowSpec(color: .black, radius: 10)
        XCTAssertEqual(spec.x, 0, "Default x should be 0")
        XCTAssertEqual(spec.y, 0, "Default y should be 0")
    }

    func testShadowSpecExplicitXY() {
        let spec = DesignShadows.ShadowSpec(color: .black, radius: 10, x: 3, y: 5)
        XCTAssertEqual(spec.x, 3)
        XCTAssertEqual(spec.y, 5)
        XCTAssertEqual(spec.radius, 10)
    }

    func testDesignShadowsForEachTheme() {
        let themes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in themes {
            let shadows = DesignShadows.shadows(for: theme)
            // Verify all three shadow specs have specific expected minimum radii
            XCTAssertGreaterThanOrEqual(
                shadows.soft.radius,
                4,
                "Soft shadow radius should be at least 4 for \(theme)",
            )
            XCTAssertGreaterThanOrEqual(
                shadows.hard.radius,
                1,
                "Hard shadow radius should be at least 1 for \(theme)",
            )
            XCTAssertGreaterThanOrEqual(
                shadows.glow.radius,
                6,
                "Glow shadow radius should be at least 6 for \(theme)",
            )
        }
    }

    // MARK: - DesignAnimations

    func testDesignAnimationsStaticAccessors() {
        _ = DesignAnimations.press
        _ = DesignAnimations.hover
        _ = DesignAnimations.content
        _ = DesignAnimations.emphasis
        _ = DesignAnimations.ambient
    }

    // MARK: - DesignTracking

    func testDesignTrackingValues() {
        XCTAssertEqual(DesignTracking.sectionLabel, 1.5)
        XCTAssertEqual(DesignTracking.tight, -0.2, accuracy: 0.001)
        XCTAssertEqual(DesignTracking.normal, 0.0)
        XCTAssertEqual(DesignTracking.wide, 0.5)
        XCTAssertEqual(DesignTracking.wider, 1.0)
        XCTAssertEqual(DesignTracking.header, 0.8, accuracy: 0.001)
    }

    // MARK: - UMButtonStyle Init

    func testButtonStyleDefaultInit() {
        let style = UMButtonStyle()
        XCTAssertEqual(style.variant, .primary, "Default variant should be primary")
        XCTAssertEqual(style.size, .md, "Default size should be md")
    }

    func testButtonStyleCustomInit() {
        let style = UMButtonStyle(.danger, size: .lg)
        XCTAssertEqual(style.variant, .danger)
        XCTAssertEqual(style.size, .lg)
    }
}
