import AppKit
import Combine
import SwiftUI

// swiftlint:disable no_magic_numbers

// MARK: - Theme Manager

@MainActor
final class ThemeManager: ObservableObject {
    @Published
    var themeMode: ThemeMode = .system
    @Published
    var accentColor: AccentColor = .blue
    @Published
    var resolvedTheme: ResolvedTheme = .darkBlue

    private var systemAppearanceObserver: NSKeyValueObservation?

    init() {
        setupSystemAppearanceObserver()
        resolve()
    }

    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        resolve()
    }

    func setAccent(_ accent: AccentColor) {
        accentColor = accent
        resolve()
    }

    private func setupSystemAppearanceObserver() {
        guard NSApp != nil else { return }
        systemAppearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.resolve()
            }
        }
    }

    private func resolve() {
        switch themeMode {
        case .light:
            resolvedTheme = .light
        case .darkBlue:
            resolvedTheme = .darkBlue
        case .darkPurple:
            resolvedTheme = .darkPurple
        case .darkBrown:
            resolvedTheme = .darkBrown
        case .darkBlack:
            resolvedTheme = .darkBlack
        case .system:
            guard let app = NSApp else {
                resolvedTheme = .darkBlue
                return
            }
            resolvedTheme =
                app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .darkBlue : .light
        }
    }

    deinit {
        systemAppearanceObserver?.invalidate()
    }
}

// MARK: - Theme Enums

enum ThemeMode: String, CaseIterable {
    case system
    case light
    case darkBlue
    case darkPurple
    case darkBrown
    case darkBlack

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .darkBlue: "Dark Blue"
        case .darkPurple: "Dark Purple"
        case .darkBrown: "Dark Brown"
        case .darkBlack: "Dark Black"
        }
    }
}

enum ResolvedTheme: String {
    case light
    case darkBlue
    case darkPurple
    case darkBrown
    case darkBlack

    var isDark: Bool {
        self != .light
    }
}

// MARK: - Accent Color

enum AccentColor: String, CaseIterable {
    case blue
    case cyan
    case green
    case magenta
    case orange
    case violet
    case red

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .blue: Color(hue: 0.72, saturation: 0.55, brightness: 0.88)
        case .cyan: Color(hue: 0.54, saturation: 0.55, brightness: 0.88)
        case .green: Color(hue: 0.40, saturation: 0.60, brightness: 0.85)
        case .magenta: Color(hue: 0.91, saturation: 0.60, brightness: 0.88)
        case .orange: Color(hue: 0.08, saturation: 0.70, brightness: 0.92)
        case .violet: Color(hue: 0.80, saturation: 0.55, brightness: 0.88)
        case .red: Color(hue: 0.03, saturation: 0.70, brightness: 0.85)
        }
    }

    var hoverColor: Color {
        switch self {
        case .blue: Color(hue: 0.72, saturation: 0.45, brightness: 0.95)
        case .cyan: Color(hue: 0.54, saturation: 0.45, brightness: 0.95)
        case .green: Color(hue: 0.40, saturation: 0.50, brightness: 0.92)
        case .magenta: Color(hue: 0.91, saturation: 0.50, brightness: 0.95)
        case .orange: Color(hue: 0.08, saturation: 0.60, brightness: 0.97)
        case .violet: Color(hue: 0.80, saturation: 0.45, brightness: 0.95)
        case .red: Color(hue: 0.03, saturation: 0.60, brightness: 0.92)
        }
    }

    var pressedColor: Color {
        switch self {
        case .blue: Color(hue: 0.72, saturation: 0.65, brightness: 0.72)
        case .cyan: Color(hue: 0.54, saturation: 0.65, brightness: 0.72)
        case .green: Color(hue: 0.40, saturation: 0.70, brightness: 0.70)
        case .magenta: Color(hue: 0.91, saturation: 0.70, brightness: 0.72)
        case .orange: Color(hue: 0.08, saturation: 0.80, brightness: 0.78)
        case .violet: Color(hue: 0.80, saturation: 0.65, brightness: 0.72)
        case .red: Color(hue: 0.03, saturation: 0.80, brightness: 0.70)
        }
    }
}

// MARK: - Design Tokens (Main Design System Object)

struct DesignTokens {
    let colors: DesignColors
    let fonts: DesignFonts
    let spacing: DesignSpacing
    let corners: DesignCorners
    let shadows: DesignShadows

    static func tokens(for theme: ResolvedTheme, accent: AccentColor) -> Self {
        Self(
            colors: .palette(for: theme, accent: accent),
            fonts: .standard,
            spacing: .standard,
            corners: .standard,
            shadows: .shadows(for: theme),
        )
    }
}

// MARK: - Design Colors

struct DesignColors {
    // Surface hierarchy
    let background: Color
    let panel: Color
    let surface: Color
    let elevated: Color
    let glass: Color

    // Interactive surfaces
    let hover: Color
    let active: Color
    let overlay: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textMuted: Color
    let textInverse: Color

    // Borders
    let borderSubtle: Color
    let borderDefault: Color
    let borderStrong: Color

    // Accent (from AccentColor)
    let accent: Color
    let accentHover: Color
    let accentPressed: Color
    let accentSubtle: Color

    // Status
    let success: Color
    let warning: Color
    let error: Color
    let successSubtle: Color
    let warningSubtle: Color
    let errorSubtle: Color

    // MARK: - Palette Factory

    static func palette(for theme: ResolvedTheme, accent: AccentColor) -> Self {
        let base = basePalette(for: theme)
        return Self(
            background: base.background,
            panel: base.panel,
            surface: base.surface,
            elevated: base.elevated,
            glass: base.glass,
            hover: base.hover,
            active: base.active,
            overlay: base.overlay,
            textPrimary: base.textPrimary,
            textSecondary: base.textSecondary,
            textTertiary: base.textTertiary,
            textMuted: base.textMuted,
            textInverse: base.textInverse,
            borderSubtle: base.borderSubtle,
            borderDefault: base.borderDefault,
            borderStrong: base.borderStrong,
            accent: accent.color,
            accentHover: accent.hoverColor,
            accentPressed: accent.pressedColor,
            accentSubtle: accent.color.opacity(0.15),
            success: base.success,
            warning: base.warning,
            error: base.error,
            successSubtle: base.successSubtle,
            warningSubtle: base.warningSubtle,
            errorSubtle: base.errorSubtle,
        )
    }

    // MARK: - Base Palettes

    private struct BasePalette {
        let background: Color
        let panel: Color
        let surface: Color
        let elevated: Color
        let glass: Color
        let hover: Color
        let active: Color
        let overlay: Color
        let textPrimary: Color
        let textSecondary: Color
        let textTertiary: Color
        let textMuted: Color
        let textInverse: Color
        let borderSubtle: Color
        let borderDefault: Color
        let borderStrong: Color
        let success: Color
        let warning: Color
        let error: Color
        let successSubtle: Color
        let warningSubtle: Color
        let errorSubtle: Color
    }

    private static func basePalette(for theme: ResolvedTheme) -> BasePalette {
        switch theme {
        case .darkBlue: darkBluePalette
        case .darkPurple: darkPurplePalette
        case .darkBrown: darkBrownPalette
        case .darkBlack: darkBlackPalette
        case .light: lightPalette
        }
    }

    // MARK: Dark Blue — hue 250° deep navy, steel-blue borders

    private static let darkBluePalette = BasePalette(
        background: Color(hue: 0.69, saturation: 0.50, brightness: 0.10),
        panel: Color(hue: 0.69, saturation: 0.42, brightness: 0.13),
        surface: Color(hue: 0.69, saturation: 0.45, brightness: 0.18),
        elevated: Color(hue: 0.69, saturation: 0.42, brightness: 0.13),
        glass: Color(hue: 0.69, saturation: 0.35, brightness: 0.16),
        hover: Color.white.opacity(0.05),
        active: Color.white.opacity(0.12),
        overlay: Color(hue: 0.69, saturation: 0.50, brightness: 0.10).opacity(0.80),
        textPrimary: Color(hue: 0.64, saturation: 0.12, brightness: 0.90),
        textSecondary: Color.white.opacity(0.76),
        textTertiary: Color.white.opacity(0.54),
        textMuted: Color.white.opacity(0.40),
        textInverse: Color(hue: 0.69, saturation: 0.50, brightness: 0.10),
        borderSubtle: Color(hue: 0.64, saturation: 0.20, brightness: 0.70).opacity(0.14),
        borderDefault: Color(hue: 0.64, saturation: 0.20, brightness: 0.70).opacity(0.10),
        borderStrong: Color(hue: 0.64, saturation: 0.20, brightness: 0.70).opacity(0.25),
        success: Color(hue: 0.40, saturation: 0.65, brightness: 0.78),
        warning: Color(hue: 0.12, saturation: 0.70, brightness: 0.85),
        error: Color(hue: 0.01, saturation: 0.70, brightness: 0.78),
        successSubtle: Color(hue: 0.40, saturation: 0.65, brightness: 0.78).opacity(0.15),
        warningSubtle: Color(hue: 0.12, saturation: 0.70, brightness: 0.85).opacity(0.15),
        errorSubtle: Color(hue: 0.01, saturation: 0.70, brightness: 0.78).opacity(0.15),
    )

    // MARK: Dark Purple — hue 300° violet, lavender borders

    private static let darkPurplePalette = BasePalette(
        background: Color(hue: 0.83, saturation: 0.55, brightness: 0.12),
        panel: Color(hue: 0.83, saturation: 0.45, brightness: 0.14),
        surface: Color(hue: 0.82, saturation: 0.50, brightness: 0.22),
        elevated: Color(hue: 0.83, saturation: 0.45, brightness: 0.14),
        glass: Color(hue: 0.83, saturation: 0.30, brightness: 0.20),
        hover: Color(hue: 0.86, saturation: 0.20, brightness: 0.85).opacity(0.05),
        active: Color(hue: 0.86, saturation: 0.30, brightness: 0.64).opacity(0.16),
        overlay: Color(hue: 0.83, saturation: 0.55, brightness: 0.12).opacity(0.80),
        textPrimary: Color(hue: 0.86, saturation: 0.18, brightness: 0.88),
        textSecondary: Color.white.opacity(0.76),
        textTertiary: Color.white.opacity(0.54),
        textMuted: Color.white.opacity(0.40),
        textInverse: Color(hue: 0.83, saturation: 0.55, brightness: 0.12),
        borderSubtle: Color(hue: 0.86, saturation: 0.20, brightness: 0.85).opacity(0.18),
        borderDefault: Color(hue: 0.86, saturation: 0.20, brightness: 0.85).opacity(0.10),
        borderStrong: Color(hue: 0.86, saturation: 0.20, brightness: 0.85).opacity(0.30),
        success: Color(hue: 0.40, saturation: 0.65, brightness: 0.78),
        warning: Color(hue: 0.12, saturation: 0.70, brightness: 0.85),
        error: Color(hue: 0.01, saturation: 0.70, brightness: 0.78),
        successSubtle: Color(hue: 0.40, saturation: 0.65, brightness: 0.78).opacity(0.15),
        warningSubtle: Color(hue: 0.12, saturation: 0.70, brightness: 0.85).opacity(0.15),
        errorSubtle: Color(hue: 0.01, saturation: 0.70, brightness: 0.78).opacity(0.15),
    )

    // MARK: Dark Brown — hue 55° walnut, amber borders

    private static let darkBrownPalette = BasePalette(
        background: Color(hue: 0.15, saturation: 0.40, brightness: 0.12),
        panel: Color(hue: 0.14, saturation: 0.35, brightness: 0.14),
        surface: Color(hue: 0.14, saturation: 0.40, brightness: 0.20),
        elevated: Color(hue: 0.14, saturation: 0.35, brightness: 0.14),
        glass: Color(hue: 0.14, saturation: 0.28, brightness: 0.18),
        hover: Color(hue: 0.17, saturation: 0.20, brightness: 0.78).opacity(0.05),
        active: Color(hue: 0.15, saturation: 0.25, brightness: 0.65).opacity(0.16),
        overlay: Color(hue: 0.15, saturation: 0.40, brightness: 0.12).opacity(0.80),
        textPrimary: Color(hue: 0.18, saturation: 0.12, brightness: 0.90),
        textSecondary: Color.white.opacity(0.76),
        textTertiary: Color.white.opacity(0.54),
        textMuted: Color.white.opacity(0.40),
        textInverse: Color(hue: 0.15, saturation: 0.40, brightness: 0.12),
        borderSubtle: Color(hue: 0.17, saturation: 0.18, brightness: 0.72).opacity(0.14),
        borderDefault: Color(hue: 0.17, saturation: 0.18, brightness: 0.72).opacity(0.10),
        borderStrong: Color(hue: 0.17, saturation: 0.18, brightness: 0.72).opacity(0.25),
        success: Color(hue: 0.40, saturation: 0.65, brightness: 0.78),
        warning: Color(hue: 0.12, saturation: 0.70, brightness: 0.85),
        error: Color(hue: 0.01, saturation: 0.70, brightness: 0.78),
        successSubtle: Color(hue: 0.40, saturation: 0.65, brightness: 0.78).opacity(0.15),
        warningSubtle: Color(hue: 0.12, saturation: 0.70, brightness: 0.85).opacity(0.15),
        errorSubtle: Color(hue: 0.01, saturation: 0.70, brightness: 0.78).opacity(0.15),
    )

    // MARK: Dark Black — near-zero chroma, purest dark

    private static let darkBlackPalette = BasePalette(
        background: Color(hue: 0.67, saturation: 0.05, brightness: 0.10),
        panel: Color(hue: 0.67, saturation: 0.05, brightness: 0.13),
        surface: Color(hue: 0.67, saturation: 0.06, brightness: 0.18),
        elevated: Color(hue: 0.67, saturation: 0.05, brightness: 0.13),
        glass: Color(hue: 0.67, saturation: 0.04, brightness: 0.16),
        hover: Color.white.opacity(0.05),
        active: Color.white.opacity(0.14),
        overlay: Color(hue: 0.67, saturation: 0.03, brightness: 0.08).opacity(0.82),
        textPrimary: Color.white.opacity(0.90),
        textSecondary: Color.white.opacity(0.72),
        textTertiary: Color.white.opacity(0.50),
        textMuted: Color.white.opacity(0.36),
        textInverse: Color(hue: 0.67, saturation: 0.05, brightness: 0.10),
        borderSubtle: Color.white.opacity(0.10),
        borderDefault: Color.white.opacity(0.08),
        borderStrong: Color.white.opacity(0.20),
        success: Color(hue: 0.40, saturation: 0.65, brightness: 0.78),
        warning: Color(hue: 0.12, saturation: 0.70, brightness: 0.85),
        error: Color(hue: 0.01, saturation: 0.70, brightness: 0.78),
        successSubtle: Color(hue: 0.40, saturation: 0.65, brightness: 0.78).opacity(0.15),
        warningSubtle: Color(hue: 0.12, saturation: 0.70, brightness: 0.85).opacity(0.15),
        errorSubtle: Color(hue: 0.01, saturation: 0.70, brightness: 0.78).opacity(0.15),
    )

    // MARK: Light — clean zinc

    private static let lightPalette = BasePalette(
        background: Color(hue: 0.0, saturation: 0.0, brightness: 0.98),
        panel: Color.white,
        surface: Color(hue: 0.0, saturation: 0.0, brightness: 0.96),
        elevated: Color.white,
        glass: Color.white.opacity(0.75),
        hover: Color.black.opacity(0.04),
        active: Color.black.opacity(0.08),
        overlay: Color.white.opacity(0.60),
        textPrimary: Color(hue: 0.0, saturation: 0.0, brightness: 0.10),
        textSecondary: Color(hue: 0.0, saturation: 0.0, brightness: 0.35),
        textTertiary: Color(hue: 0.0, saturation: 0.0, brightness: 0.55),
        textMuted: Color(hue: 0.0, saturation: 0.0, brightness: 0.70),
        textInverse: Color.white,
        borderSubtle: Color.black.opacity(0.06),
        borderDefault: Color.black.opacity(0.10),
        borderStrong: Color.black.opacity(0.18),
        success: Color(hue: 0.40, saturation: 0.70, brightness: 0.55),
        warning: Color(hue: 0.10, saturation: 0.80, brightness: 0.60),
        error: Color(hue: 0.01, saturation: 0.80, brightness: 0.58),
        successSubtle: Color(hue: 0.40, saturation: 0.70, brightness: 0.55).opacity(0.10),
        warningSubtle: Color(hue: 0.10, saturation: 0.80, brightness: 0.60).opacity(0.10),
        errorSubtle: Color(hue: 0.01, saturation: 0.80, brightness: 0.58).opacity(0.10),
    )
}

// MARK: - Design Fonts — SF Pro (no rounded)

struct DesignFonts {
    // Headings
    let title1: Font = .system(size: 24, weight: .bold)
    let title2: Font = .system(size: 20, weight: .bold)
    let title3: Font = .system(size: 17, weight: .semibold)
    let headline: Font = .system(size: 15, weight: .semibold)

    // Body
    let body: Font = .system(size: 14, weight: .regular)
    let callout: Font = .system(size: 13, weight: .regular)
    let footnote: Font = .system(size: 12, weight: .regular)
    let caption: Font = .system(size: 11, weight: .regular)

    // Mono
    let mono: Font = .system(size: 13, weight: .medium, design: .monospaced)
    let monoSmall: Font = .system(size: 11, weight: .medium, design: .monospaced)

    /// Section label (used with .tracking(DesignTracking.sectionLabel) + .textCase(.uppercase))
    let sectionLabel: Font = .system(size: 11, weight: .semibold)

    static let standard = Self()
}

// MARK: - Design Spacing

struct DesignSpacing {
    let xs: CGFloat = 4
    let sm: CGFloat = 8
    let md: CGFloat = 12
    let lg: CGFloat = 16
    let xl: CGFloat = 20
    let xxl: CGFloat = 24
    let xxxl: CGFloat = 32

    static let standard = Self()
}

// MARK: - Design Corners

struct DesignCorners {
    let sm: CGFloat = 6
    let md: CGFloat = 8
    let lg: CGFloat = 12
    let xl: CGFloat = 16
    let full: CGFloat = 999

    static let standard = Self()
}

// MARK: - Design Shadows

struct DesignShadows {
    let soft: ShadowSpec
    let hard: ShadowSpec
    let glow: ShadowSpec

    struct ShadowSpec {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
            self.color = color
            self.radius = radius
            self.x = x
            self.y = y
        }
    }

    static func shadows(for theme: ResolvedTheme) -> Self {
        switch theme {
        case .darkBlue:
            Self(
                soft: ShadowSpec(
                    color: Color(hue: 0.69, saturation: 0.30, brightness: 0.08).opacity(0.42),
                    radius: 14,
                    y: 6,
                ),
                hard: ShadowSpec(
                    color: Color(hue: 0.69, saturation: 0.30, brightness: 0.05).opacity(0.58),
                    radius: 24,
                    y: 12,
                ),
                glow: ShadowSpec(color: Color.clear, radius: 12),
            )

        case .darkPurple:
            Self(
                soft: ShadowSpec(color: Color.black.opacity(0.38), radius: 14, y: 6),
                hard: ShadowSpec(color: Color.black.opacity(0.55), radius: 24, y: 12),
                glow: ShadowSpec(color: Color.clear, radius: 12),
            )

        case .darkBrown:
            Self(
                soft: ShadowSpec(
                    color: Color(hue: 0.14, saturation: 0.20, brightness: 0.08).opacity(0.42),
                    radius: 14,
                    y: 6,
                ),
                hard: ShadowSpec(
                    color: Color(hue: 0.14, saturation: 0.20, brightness: 0.05).opacity(0.58),
                    radius: 24,
                    y: 12,
                ),
                glow: ShadowSpec(color: Color.clear, radius: 12),
            )

        case .darkBlack:
            Self(
                soft: ShadowSpec(color: Color.black.opacity(0.45), radius: 14, y: 6),
                hard: ShadowSpec(color: Color.black.opacity(0.60), radius: 24, y: 12),
                glow: ShadowSpec(color: Color.clear, radius: 12),
            )

        case .light:
            Self(
                soft: ShadowSpec(color: Color.black.opacity(0.08), radius: 8, y: 3),
                hard: ShadowSpec(color: Color.black.opacity(0.15), radius: 16, y: 6),
                glow: ShadowSpec(color: Color.clear, radius: 8),
            )
        }
    }
}

// MARK: - Design Animations

enum DesignAnimations {
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let hover = Animation.easeOut(duration: 0.15)
    static let content = Animation.easeInOut(duration: 0.2)
    static let emphasis = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let ambient = Animation.easeInOut(duration: 1.5)
}

// MARK: - Standard Tracking Values

enum DesignTracking {
    static let sectionLabel: CGFloat = 1.5
    static let tight: CGFloat = -0.2
    static let normal: CGFloat = 0.0
    static let wide: CGFloat = 0.5
    static let wider: CGFloat = 1.0
    static let header: CGFloat = 0.8
}

// MARK: - Environment Integration

extension EnvironmentValues {
    @Entry
    var design: DesignTokens = .tokens(for: .darkBlue, accent: .blue)
}

struct ThemedModifier: ViewModifier {
    @ObservedObject
    var themeManager: ThemeManager

    func body(content: Content) -> some View {
        content
            .environment(\.design, DesignTokens.tokens(
                for: themeManager.resolvedTheme,
                accent: themeManager.accentColor,
            ))
            .environmentObject(themeManager)
    }
}

extension View {
    func themed(themeManager: ThemeManager) -> some View {
        modifier(ThemedModifier(themeManager: themeManager))
    }
}
