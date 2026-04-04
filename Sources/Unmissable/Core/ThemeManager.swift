import AppKit
import Observation
import SwiftUI

// swiftlint:disable no_magic_numbers

// MARK: - Theme Manager

@Observable
final class ThemeManager {
    var themeMode: ThemeMode = .system
    var accentColor: AccentColor = .blue
    var resolvedTheme: ResolvedTheme = .darkBlue

    @ObservationIgnored
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
        let previousTheme = resolvedTheme

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

        if resolvedTheme != previousTheme {
            AppDiagnostics.record(component: "ThemeManager", phase: "themeChanged") {
                [
                    "from": previousTheme.rawValue,
                    "to": self.resolvedTheme.rawValue,
                    "mode": self.themeMode.rawValue,
                ]
            }
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
