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
        let (h, s, b) = hsbComponents
        return Color(hue: h, saturation: s, brightness: b)
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

    /// CSS hex representation of the accent color for use in HTML rendering.
    /// Derived from the same HSB values as `color` to maintain design system consistency.
    var cssHex: String {
        let (h, s, b) = hsbComponents
        let (r, g, bl) = Self.hsbToRGB(h: h, s: s, b: b)
        return String(format: "#%02X%02X%02X", r, g, bl)
    }

    private var hsbComponents: (Double, Double, Double) {
        switch self {
        case .blue: (0.72, 0.55, 0.88)
        case .cyan: (0.54, 0.55, 0.88)
        case .green: (0.40, 0.60, 0.85)
        case .magenta: (0.91, 0.60, 0.88)
        case .orange: (0.08, 0.70, 0.92)
        case .violet: (0.80, 0.55, 0.88)
        case .red: (0.03, 0.70, 0.85)
        }
    }

    private static func hsbToRGB(h: Double, s: Double, b: Double) -> (Int, Int, Int) {
        let c = b * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = b - c
        let (r1, g1, b1): (Double, Double, Double)
        let hue6 = h * 6
        switch hue6 {
        case 0 ..< 1: (r1, g1, b1) = (c, x, 0)
        case 1 ..< 2: (r1, g1, b1) = (x, c, 0)
        case 2 ..< 3: (r1, g1, b1) = (0, c, x)
        case 3 ..< 4: (r1, g1, b1) = (0, x, c)
        case 4 ..< 5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return (
            Int((r1 + m) * 255),
            Int((g1 + m) * 255),
            Int((b1 + m) * 255),
        )
    }
}
