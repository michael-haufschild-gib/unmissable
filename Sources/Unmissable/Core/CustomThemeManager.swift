import AppKit
import Combine
import SwiftUI

// MARK: - Custom Theme Manager (100% Custom Styling)

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published
    var currentTheme: AppTheme = .system
    @Published
    var effectiveTheme: EffectiveTheme = .dark

    private var cancellables = Set<AnyCancellable>()
    private var systemAppearanceObserver: NSKeyValueObservation?

    private init() {
        setupSystemAppearanceObserver()
        updateEffectiveTheme()
    }

    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        updateEffectiveTheme()
    }

    private func setupSystemAppearanceObserver() {
        // Skip setting up observer when NSApp isn't fully initialized (e.g. during tests)
        guard NSApplication.shared.delegate != nil
        else { return }

        systemAppearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.updateEffectiveTheme()
            }
        }
    }

    private func updateEffectiveTheme() {
        switch currentTheme {
        case .light:
            effectiveTheme = .light
        case .dark:
            effectiveTheme = .dark
        case .system:
            // When NSApp isn't fully initialized (e.g. tests), default to dark
            if NSApplication.shared.delegate == nil {
                effectiveTheme = .dark
            } else {
                effectiveTheme =
                    NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? .dark : .light
            }
        }
    }

    deinit {
        systemAppearanceObserver?.invalidate()
    }
}

// MARK: - Theme Types

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum EffectiveTheme {
    case light, dark
}

// MARK: - Design System — "Beacon"

struct CustomDesign {
    let colors: CustomColors
    let fonts: CustomFonts
    let spacing: CustomSpacing
    let corners: CustomCorners
    let shadows: CustomShadows

    static func design(for theme: EffectiveTheme) -> Self {
        switch theme {
        case .light:
            Self(
                colors: .lightTheme,
                fonts: .standard,
                spacing: .standard,
                corners: .standard,
                shadows: .light
            )

        case .dark:
            Self(
                colors: .darkTheme,
                fonts: .standard,
                spacing: .standard,
                corners: .standard,
                shadows: .dark
            )
        }
    }
}

// MARK: - Colors — Zinc + Signal Orange

struct CustomColors {
    // Backgrounds
    let background: Color
    let backgroundSecondary: Color
    let backgroundTertiary: Color
    let backgroundCard: Color
    let backgroundButton: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textInverse: Color

    // Accents
    let accent: Color
    let accentSecondary: Color
    let success: Color
    let warning: Color
    let error: Color

    // Borders & Dividers
    let border: Color
    let borderSecondary: Color
    let divider: Color

    // Interactive States
    let interactive: Color
    let interactiveHover: Color
    let interactivePressed: Color
    let interactiveDisabled: Color

    // MARK: - Dark Theme — Zinc + Signal Orange

    static let darkTheme = Self(
        // Zinc-scale backgrounds
        background: Color(red: 0.035, green: 0.035, blue: 0.043), // #09090B zinc-950
        backgroundSecondary: Color(red: 0.094, green: 0.094, blue: 0.106), // #18181B zinc-900
        backgroundTertiary: Color(red: 0.153, green: 0.153, blue: 0.165), // #27272A zinc-800
        backgroundCard: Color(red: 0.078, green: 0.078, blue: 0.086), // #141416 between 950-900
        backgroundButton: Color(red: 0.153, green: 0.153, blue: 0.165), // #27272A zinc-800

        // Zinc-scale text
        textPrimary: Color(red: 0.980, green: 0.980, blue: 0.980), // #FAFAFA zinc-50
        textSecondary: Color(red: 0.631, green: 0.631, blue: 0.667), // #A1A1AA zinc-400
        textTertiary: Color(red: 0.322, green: 0.322, blue: 0.357), // #52525B zinc-600
        textInverse: Color(red: 0.035, green: 0.035, blue: 0.043), // #09090B zinc-950

        // Signal orange accent system
        accent: Color(red: 0.976, green: 0.451, blue: 0.086), // #F97316 orange-500
        accentSecondary: Color(red: 0.984, green: 0.573, blue: 0.235), // #FB923C orange-400 (AA on dark)
        success: Color(red: 0.133, green: 0.773, blue: 0.369), // #22C55E green-500
        warning: Color(red: 0.984, green: 0.749, blue: 0.141), // #FBBF24 amber-400
        error: Color(red: 0.937, green: 0.267, blue: 0.267), // #EF4444 red-500

        // Borders — subtle white overlay
        border: Color.white.opacity(0.06),
        borderSecondary: Color.white.opacity(0.04),
        divider: Color.white.opacity(0.08),

        // Interactive — orange states
        interactive: Color(red: 0.976, green: 0.451, blue: 0.086), // #F97316
        interactiveHover: Color(red: 0.984, green: 0.573, blue: 0.235), // #FB923C lighter
        interactivePressed: Color(red: 0.918, green: 0.345, blue: 0.047), // #EA580C darker
        interactiveDisabled: Color(red: 0.322, green: 0.322, blue: 0.357) // #52525B zinc-600
    )

    // MARK: - Light Theme — Clean Zinc + Warm Orange

    static let lightTheme = Self(
        // Light zinc-scale backgrounds
        background: Color(red: 0.980, green: 0.980, blue: 0.980), // #FAFAFA zinc-50
        backgroundSecondary: Color(red: 0.953, green: 0.953, blue: 0.961), // #F4F4F5 zinc-100
        backgroundTertiary: Color(red: 0.894, green: 0.894, blue: 0.906), // #E4E4E7 zinc-200
        backgroundCard: Color.white,
        backgroundButton: Color(red: 0.953, green: 0.953, blue: 0.961), // #F4F4F5 zinc-100

        // Dark text on light
        textPrimary: Color(red: 0.094, green: 0.094, blue: 0.106), // #18181B zinc-900
        textSecondary: Color(red: 0.322, green: 0.322, blue: 0.357), // #52525B zinc-600
        textTertiary: Color(red: 0.631, green: 0.631, blue: 0.667), // #A1A1AA zinc-400
        textInverse: Color.white,

        // Darker orange for light backgrounds (better contrast)
        accent: Color(red: 0.918, green: 0.345, blue: 0.047), // #EA580C orange-600
        accentSecondary: Color(red: 0.976, green: 0.451, blue: 0.086), // #F97316 orange-500
        success: Color(red: 0.082, green: 0.647, blue: 0.290), // #15803D green-700
        warning: Color(red: 0.855, green: 0.580, blue: 0.024), // #D97706 amber-600
        error: Color(red: 0.863, green: 0.149, blue: 0.149), // #DC2626 red-600

        // Clean borders
        border: Color(red: 0.894, green: 0.894, blue: 0.906), // #E4E4E7 zinc-200
        borderSecondary: Color(red: 0.953, green: 0.953, blue: 0.961), // #F4F4F5 zinc-100
        divider: Color(red: 0.894, green: 0.894, blue: 0.906), // #E4E4E7 zinc-200

        // Interactive — orange states (darker for light bg)
        interactive: Color(red: 0.918, green: 0.345, blue: 0.047), // #EA580C
        interactiveHover: Color(red: 0.976, green: 0.451, blue: 0.086), // #F97316 lighter
        interactivePressed: Color(red: 0.780, green: 0.271, blue: 0.012), // #C2450A darker
        interactiveDisabled: Color(red: 0.631, green: 0.631, blue: 0.667) // #A1A1AA zinc-400
    )
}

// MARK: - Typography — SF Rounded headings, SF Mono timestamps

struct CustomFonts {
    // Headings — rounded for warmth and distinction
    let largeTitle: Font = .system(size: 34, weight: .bold, design: .rounded)
    let title1: Font = .system(size: 28, weight: .bold, design: .rounded)
    let title2: Font = .system(size: 22, weight: .bold, design: .rounded)
    let title3: Font = .system(size: 20, weight: .semibold, design: .rounded)
    let headline: Font = .system(size: 17, weight: .semibold, design: .rounded)

    // Body — default for readability
    let subheadline: Font = .system(size: 15, weight: .medium, design: .default)
    let body: Font = .system(size: 17, weight: .regular, design: .default)
    let callout: Font = .system(size: 16, weight: .regular, design: .default)
    let footnote: Font = .system(size: 13, weight: .regular, design: .default)
    let caption1: Font = .system(size: 12, weight: .regular, design: .default)
    let caption2: Font = .system(size: 11, weight: .regular, design: .default)

    // Monospaced — timestamps, countdown, technical data
    let mono: Font = .system(size: 13, weight: .medium, design: .monospaced)
    let monoLarge: Font = .system(size: 16, weight: .medium, design: .monospaced)
    let monoTimestamp: Font = .system(size: 12, weight: .medium, design: .monospaced)

    static let standard = Self()
}

// MARK: - Spacing

struct CustomSpacing {
    let xs: CGFloat = 4
    let sm: CGFloat = 8
    let md: CGFloat = 12
    let lg: CGFloat = 16
    let xl: CGFloat = 20
    let xxl: CGFloat = 24
    let xxxl: CGFloat = 32

    static let standard = Self()
}

// MARK: - Corner Radius

struct CustomCorners {
    let small: CGFloat = 4
    let medium: CGFloat = 8
    let large: CGFloat = 12
    let extraLarge: CGFloat = 16
    let circle: CGFloat = 999

    static let standard = Self()
}

// MARK: - Shadows

struct CustomShadows {
    let color: Color
    let radius: CGFloat
    let offset: CGSize

    static let light = Self(
        color: Color.black.opacity(0.06),
        radius: 6,
        offset: CGSize(width: 0, height: 2)
    )

    static let dark = Self(
        color: Color.black.opacity(0.3),
        radius: 12,
        offset: CGSize(width: 0, height: 4)
    )
}

extension EnvironmentValues {
    @Entry
    var customDesign: CustomDesign = .design(for: .dark)
}

// MARK: - Custom Theme Modifier

struct CustomThemeModifier: ViewModifier {
    @ObservedObject
    private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        content
            .environment(\.customDesign, CustomDesign.design(for: themeManager.effectiveTheme))
            .environmentObject(themeManager)
    }
}

extension View {
    func customThemedEnvironment() -> some View {
        modifier(CustomThemeModifier())
    }
}
