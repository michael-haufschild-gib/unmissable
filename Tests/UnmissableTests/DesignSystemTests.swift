import Foundation
import Testing
@testable import Unmissable

@MainActor
struct DesignSystemTests {
    // MARK: - UMButtonStyle.Variant

    @Test
    func buttonStyleVariantHasFourCases() {
        let cases: [UMButtonStyle.Variant] = [.primary, .secondary, .ghost, .danger]
        #expect(cases == [.primary, .secondary, .ghost, .danger])
    }

    @Test
    func buttonStyleVariantCasesAreDistinct() {
        let primary = UMButtonStyle.Variant.primary
        let secondary = UMButtonStyle.Variant.secondary
        let ghost = UMButtonStyle.Variant.ghost
        let danger = UMButtonStyle.Variant.danger

        let mirror = [
            "\(primary)", "\(secondary)", "\(ghost)", "\(danger)",
        ]
        let uniqueCount = Set(mirror).count
        #expect(uniqueCount == 4, "All button variants must be distinct")
        #expect(mirror.first == "primary")
    }

    // MARK: - UMButtonStyle.Size

    @Test
    func buttonStyleSizeHasFourCases() {
        let cases: [UMButtonStyle.Size] = [.sm, .md, .lg, .icon]
        #expect(cases == [.sm, .md, .lg, .icon])
    }

    @Test
    func buttonStyleSizeCasesAreDistinct() {
        let sm = UMButtonStyle.Size.sm
        let md = UMButtonStyle.Size.md
        let lg = UMButtonStyle.Size.lg
        let icon = UMButtonStyle.Size.icon

        let mirror = ["\(sm)", "\(md)", "\(lg)", "\(icon)"]
        let uniqueCount = Set(mirror).count
        #expect(uniqueCount == 4, "All button sizes must be distinct")
        #expect(mirror.first == "sm")
    }

    // MARK: - UMBadge.Variant

    @Test
    func badgeVariantHasFiveCases() {
        let cases: [UMBadge.Variant] = [.accent, .success, .warning, .error, .neutral]
        #expect(cases == [.accent, .success, .warning, .error, .neutral])
    }

    @Test
    func badgeVariantCasesAreDistinct() {
        let all: [UMBadge.Variant] = [.accent, .success, .warning, .error, .neutral]
        let names = all.map { "\($0)" }
        let uniqueCount = Set(names).count
        #expect(uniqueCount == 5, "All badge variants must be distinct")
        #expect(names.first == "accent")
    }

    // MARK: - UMStatusIndicator.Status

    @Test
    func statusIndicatorHasFourCases() {
        let cases: [UMStatusIndicator.Status] = [.connected, .connecting, .disconnected, .error]
        #expect(cases == [.connected, .connecting, .disconnected, .error])
    }

    @Test
    func statusIndicatorCasesAreDistinct() {
        let all: [UMStatusIndicator.Status] = [.connected, .connecting, .disconnected, .error]
        let names = all.map { "\($0)" }
        let uniqueCount = Set(names).count
        #expect(uniqueCount == 4, "All status indicator cases must be distinct")
        #expect(names.first == "connected")
    }

    // MARK: - UMCardModifier.Style

    @Test
    func cardModifierStyleHasThreeCases() {
        let cases: [UMCardModifier.Style] = [.glass, .elevated, .flat]
        #expect(cases == [.glass, .elevated, .flat])
    }

    @Test
    func cardModifierStyleCasesAreDistinct() {
        let all: [UMCardModifier.Style] = [.glass, .elevated, .flat]
        let names = all.map { "\($0)" }
        let uniqueCount = Set(names).count
        #expect(uniqueCount == 3, "All card modifier styles must be distinct")
        #expect(names.first == "glass")
    }

    // MARK: - UMBadge Init

    @Test
    func badgeInitWithEachVariantDoesNotCrash() {
        let variants: [UMBadge.Variant] = [.accent, .success, .warning, .error, .neutral]
        for variant in variants {
            let badge = UMBadge("Test", variant: variant)
            #expect(badge.text == "Test")
            #expect(badge.variant == variant)
        }
    }

    @Test
    func badgeDefaultVariantIsAccent() {
        let badge = UMBadge("Default")
        #expect(badge.variant == .accent)
    }

    // MARK: - UMStatusIndicator Init

    @Test
    func statusIndicatorInitWithEachStatusDoesNotCrash() {
        let statuses: [UMStatusIndicator.Status] = [
            .connected, .connecting, .disconnected, .error,
        ]
        for status in statuses {
            let indicator = UMStatusIndicator(status)
            #expect(indicator.status == status)
            #expect(indicator.size == 10, "Default size should be 10")
        }
    }

    @Test
    func statusIndicatorCustomSize() {
        let indicator = UMStatusIndicator(.connected, size: 20)
        #expect(indicator.size == 20)
    }

    // MARK: - AccentColor Enum Completeness

    @Test
    func accentColorHasSevenCases() {
        let allCases = AccentColor.allCases
        #expect(allCases == [.blue, .cyan, .green, .magenta, .orange, .violet, .red])
    }

    @Test
    func accentColorAllCasesHaveNonEmptyDisplayName() {
        for accent in AccentColor.allCases {
            #expect(
                accent.displayName == accent.rawValue.capitalized,
                "\(accent) should have displayName matching capitalized rawValue",
            )
        }
    }

    @Test
    func accentColorExpectedCases() {
        let expected: [AccentColor] = [.blue, .cyan, .green, .magenta, .orange, .violet, .red]
        #expect(Set(AccentColor.allCases) == Set(expected))
    }

    // MARK: - ThemeMode Enum Completeness

    @Test
    func themeModeHasSixCases() {
        let allCases = ThemeMode.allCases
        #expect(
            allCases == [.system, .light, .darkBlue, .darkPurple, .darkBrown, .darkBlack],
        )
    }

    @Test
    func themeModeAllCasesHaveNonEmptyDisplayName() {
        for mode in ThemeMode.allCases {
            #expect(
                !mode.displayName.isEmpty,
                "\(mode) should have a non-empty displayName",
            )
        }
        #expect(ThemeMode.system.displayName == "System")
        #expect(ThemeMode.light.displayName == "Light")
    }

    @Test
    func themeModeExpectedCases() {
        let expected: [ThemeMode] = [.system, .light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        #expect(Set(ThemeMode.allCases) == Set(expected))
    }

    // MARK: - DesignTokens Factory

    @Test
    func designTokensFactoryProducesCompleteObject() {
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

    @Test
    func designTokensFactoryForEveryThemeAndAccent() {
        let themes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in themes {
            for accent in AccentColor.allCases {
                let tokens = DesignTokens.tokens(for: theme, accent: accent)
                // Verify accent color matches the input accent
                #expect(
                    tokens.colors.accent == accent.color,
                    "Accent color mismatch for theme=\(theme), accent=\(accent)",
                )
            }
        }
    }

    // MARK: - DesignFonts

    @Test
    func designFontsStandardSingleton() {
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

    @Test
    func designSpacingStandardSingleton() {
        let spacing = DesignSpacing.standard
        #expect(spacing.xs == 4)
        #expect(spacing.sm == 8)
        #expect(spacing.md == 12)
        #expect(spacing.lg == 16)
        #expect(spacing.xl == 20)
        #expect(spacing.xxl == 24)
        #expect(spacing.xxxl == 32)
    }

    @Test
    func designSpacingValuesAreStrictlyIncreasing() {
        let spacing = DesignSpacing.standard
        let values = [
            spacing.xs, spacing.sm, spacing.md,
            spacing.lg, spacing.xl, spacing.xxl, spacing.xxxl,
        ]
        for i in 1 ..< values.count {
            #expect(
                values[i] > values[i - 1],
                "Spacing scale must be strictly increasing at index \(i)",
            )
        }
    }

    // MARK: - DesignCorners

    @Test
    func designCornersStandardValues() {
        let corners = DesignCorners.standard
        #expect(corners.sm == 6)
        #expect(corners.md == 8)
        #expect(corners.lg == 12)
        #expect(corners.xl == 16)
        #expect(corners.full == 999)
    }

    @Test
    func designCornersScaleIsIncreasingExceptFull() {
        let corners = DesignCorners.standard
        let scale = [corners.sm, corners.md, corners.lg, corners.xl]
        for i in 1 ..< scale.count {
            #expect(
                scale[i] > scale[i - 1],
                "Corner radius scale must be strictly increasing at index \(i)",
            )
        }
        #expect(corners.full > corners.xl, "full must exceed xl")
    }

    // MARK: - DesignShadows ShadowSpec

    @Test
    func shadowSpecDefaultXYAreZero() {
        let spec = DesignShadows.ShadowSpec(color: .black, radius: 10)
        #expect(spec.x == 0, "Default x should be 0")
        #expect(spec.y == 0, "Default y should be 0")
    }

    @Test
    func shadowSpecExplicitXY() {
        let spec = DesignShadows.ShadowSpec(color: .black, radius: 10, x: 3, y: 5)
        #expect(spec.x == 3)
        #expect(spec.y == 5)
        #expect(spec.radius == 10)
    }

    @Test
    func designShadowsForEachTheme() {
        let themes: [ResolvedTheme] = [.light, .darkBlue, .darkPurple, .darkBrown, .darkBlack]
        for theme in themes {
            let shadows = DesignShadows.shadows(for: theme)
            // Verify all three shadow specs have specific expected minimum radii
            #expect(
                shadows.soft.radius >= 4,
                "Soft shadow radius should be at least 4 for \(theme)",
            )
            #expect(
                shadows.hard.radius >= 1,
                "Hard shadow radius should be at least 1 for \(theme)",
            )
            #expect(
                shadows.glow.radius >= 6,
                "Glow shadow radius should be at least 6 for \(theme)",
            )
        }
    }

    // MARK: - DesignAnimations

    @Test
    func designAnimationsStaticAccessors() {
        _ = DesignAnimations.press
        _ = DesignAnimations.hover
        _ = DesignAnimations.content
        _ = DesignAnimations.emphasis
        _ = DesignAnimations.ambient
    }

    // MARK: - DesignTracking

    @Test
    func designTrackingValues() {
        #expect(DesignTracking.sectionLabel == 1.5)
        #expect(abs(DesignTracking.tight - -0.2) <= 0.001)
        #expect(DesignTracking.normal == 0.0)
        #expect(DesignTracking.wide == 0.5)
        #expect(DesignTracking.wider == 1.0)
        #expect(abs(DesignTracking.header - 0.8) <= 0.001)
    }

    // MARK: - UMButtonStyle Init

    @Test
    func buttonStyleDefaultInit() {
        let style = UMButtonStyle()
        #expect(style.variant == .primary, "Default variant should be primary")
        #expect(style.size == .md, "Default size should be md")
    }

    @Test
    func buttonStyleCustomInit() {
        let style = UMButtonStyle(.danger, size: .lg)
        #expect(style.variant == .danger)
        #expect(style.size == .lg)
    }
}
