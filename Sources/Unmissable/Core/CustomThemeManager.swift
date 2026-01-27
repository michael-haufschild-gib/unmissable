import AppKit
import Combine
import SwiftUI

// MARK: - Custom Theme Manager (100% Custom Styling)

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme = .system
    @Published var effectiveTheme: EffectiveTheme = .dark

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
        // Skip setting up observer during testing to avoid crashes
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSApplication.shared.delegate != nil
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
            // Check if NSApp is available during testing
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                effectiveTheme = .dark // Default to dark during testing
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

// MARK: - Custom Design System (No System Dependencies)

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
                fonts: .systemFonts,
                spacing: .standard,
                corners: .modern,
                shadows: .subtle
            )
        case .dark:
            Self(
                colors: .darkTheme,
                fonts: .systemFonts,
                spacing: .standard,
                corners: .modern,
                shadows: .dark
            )
        }
    }
}

// MARK: - Custom Colors (Completely Custom - No System Colors)

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

    // MARK: - Light Theme (Professional, Clean)

    static let lightTheme = Self(
        // Clean white backgrounds with subtle distinction
        background: Color.white,
        backgroundSecondary: Color(red: 0.98, green: 0.98, blue: 0.99),
        backgroundTertiary: Color(red: 0.95, green: 0.96, blue: 0.97),
        backgroundCard: Color.white,
        backgroundButton: Color(red: 0.97, green: 0.97, blue: 0.98),

        // Professional dark text
        textPrimary: Color(red: 0.11, green: 0.11, blue: 0.13),
        textSecondary: Color(red: 0.37, green: 0.37, blue: 0.39),
        textTertiary: Color(red: 0.55, green: 0.55, blue: 0.58),
        textInverse: Color.white,

        // AI Wave purple accent adapted for light theme
        accent: Color(red: 0.502, green: 0.353, blue: 0.961), // #805AF5 same as dark
        accentSecondary: Color(red: 0.702, green: 0.553, blue: 0.871), // Slightly darker purple
        success: Color(red: 0.243, green: 0.718, blue: 0.369), // Same as AI Wave
        warning: Color(red: 0.918, green: 0.584, blue: 0.063), // Slightly darker for contrast
        error: Color(red: 0.863, green: 0.196, blue: 0.208), // Better contrast

        // Clean borders
        border: Color(red: 0.89, green: 0.89, blue: 0.91),
        borderSecondary: Color(red: 0.94, green: 0.94, blue: 0.96),
        divider: Color(red: 0.92, green: 0.92, blue: 0.94),

        // Interactive states matching accent
        interactive: Color(red: 0.502, green: 0.353, blue: 0.961), // #805AF5
        interactiveHover: Color(red: 0.427, green: 0.278, blue: 0.945), // Darker on hover for light
        interactivePressed: Color(red: 0.376, green: 0.235, blue: 0.922), // Even darker when pressed
        interactiveDisabled: Color(red: 0.78, green: 0.78, blue: 0.8)
    )

    // MARK: - Dark Theme (AI Wave Inspired)

    static let darkTheme = Self(
        // Rich, deep dark backgrounds inspired by AI Wave
        background: Color(red: 0.055, green: 0.047, blue: 0.082), // #0E0C15 AI Wave primary bg
        backgroundSecondary: Color(red: 0.129, green: 0.129, blue: 0.153), // #21242D AI Wave dark
        backgroundTertiary: Color(red: 0.180, green: 0.192, blue: 0.239), // #2E313D AI Wave less dark
        backgroundCard: Color(red: 0.086, green: 0.086, blue: 0.110), // Slightly lighter than bg
        backgroundButton: Color(red: 0.172, green: 0.192, blue: 0.247), // #2C313F AI Wave button

        // AI Wave inspired text colors
        textPrimary: Color.white, // #ffffff AI Wave headings
        textSecondary: Color(red: 0.737, green: 0.765, blue: 0.843), // #BCC3D7 AI Wave body
        textTertiary: Color(red: 0.337, green: 0.369, blue: 0.471), // #565e78 AI Wave off text
        textInverse: Color(red: 0.055, green: 0.047, blue: 0.082),

        // AI Wave purple gradient accent system
        accent: Color(red: 0.502, green: 0.353, blue: 0.961), // #805AF5 AI Wave primary
        accentSecondary: Color(red: 0.804, green: 0.600, blue: 1.0), // #CD99FF AI Wave secondary
        success: Color(red: 0.243, green: 0.718, blue: 0.369), // #3EB75E AI Wave success
        warning: Color(red: 1.0, green: 0.784, blue: 0.463), // #FFC876 AI Wave warning
        error: Color(red: 1.0, green: 0.0, blue: 0.012), // #FF0003 AI Wave danger

        // Subtle borders with AI Wave influence
        border: Color(red: 1.0, green: 1.0, blue: 1.0).opacity(0.05), // AI Wave border
        borderSecondary: Color(red: 0.118, green: 0.118, blue: 0.118), // #1E1E1E
        divider: Color(red: 1.0, green: 1.0, blue: 1.0).opacity(0.08),

        // Interactive states with purple gradient influence
        interactive: Color(red: 0.502, green: 0.353, blue: 0.961), // #805AF5
        interactiveHover: Color(red: 0.627, green: 0.471, blue: 0.976), // Brighter purple
        interactivePressed: Color(red: 0.376, green: 0.235, blue: 0.945), // Darker purple
        interactiveDisabled: Color(red: 0.4, green: 0.4, blue: 0.42)
    )
}

// MARK: - Custom Typography

struct CustomFonts {
    let largeTitle: Font = .system(size: 34, weight: .bold, design: .default)
    let title1: Font = .system(size: 28, weight: .bold, design: .default)
    let title2: Font = .system(size: 22, weight: .bold, design: .default)
    let title3: Font = .system(size: 20, weight: .semibold, design: .default)
    let headline: Font = .system(size: 17, weight: .semibold, design: .default)
    let subheadline: Font = .system(size: 15, weight: .medium, design: .default)
    let body: Font = .system(size: 17, weight: .regular, design: .default)
    let callout: Font = .system(size: 16, weight: .regular, design: .default)
    let footnote: Font = .system(size: 13, weight: .regular, design: .default)
    let caption1: Font = .system(size: 12, weight: .regular, design: .default)
    let caption2: Font = .system(size: 11, weight: .regular, design: .default)

    // Monospaced
    let mono: Font = .system(size: 13, weight: .medium, design: .monospaced)
    let monoLarge: Font = .system(size: 16, weight: .medium, design: .monospaced)

    static let systemFonts = Self()
}

// MARK: - Custom Spacing

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

// MARK: - Custom Corner Radius (AI Wave Inspired)

struct CustomCorners {
    let small: CGFloat = 4 // AI Wave small radius
    let medium: CGFloat = 8 // AI Wave default button radius
    let large: CGFloat = 12 // AI Wave card radius
    let extraLarge: CGFloat = 16 // AI Wave big radius
    let circle: CGFloat = 999

    static let modern = Self()
}

// MARK: - Custom Shadows

struct CustomShadows {
    let color: Color
    let radius: CGFloat
    let offset: CGSize

    static let subtle = Self(
        color: Color.black.opacity(0.08),
        radius: 8,
        offset: CGSize(width: 0, height: 2)
    )

    static let dark = Self(
        color: Color.black.opacity(0.25),
        radius: 12,
        offset: CGSize(width: 0, height: 4)
    )
}

// MARK: - Environment Integration

struct CustomDesignEnvironment: EnvironmentKey {
    static let defaultValue: CustomDesign = .design(for: .dark)
}

extension EnvironmentValues {
    var customDesign: CustomDesign {
        get { self[CustomDesignEnvironment.self] }
        set { self[CustomDesignEnvironment.self] = newValue }
    }
}

// MARK: - Custom Theme Modifier

struct CustomThemeModifier: ViewModifier {
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        content
            .environment(\.customDesign, CustomDesign.design(for: themeManager.effectiveTheme))
    }
}

extension View {
    func customThemedEnvironment() -> some View {
        modifier(CustomThemeModifier())
    }
}
