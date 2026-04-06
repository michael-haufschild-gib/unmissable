import SwiftUI

// MARK: - Glass Modifier

/// Applies the glassmorphism recipe: native material + theme-tinted overlay +
/// inset highlight + multi-layer shadow.
struct UMGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.design)
    private var design

    private enum Metrics {
        static let glassOverlayOpacity: Double = 0.6
        static let highlightTopOpacity: Double = 0.06
        static let strokeWidth: CGFloat = 0.5
    }

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(design.colors.glass.opacity(Metrics.glassOverlayOpacity))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(Metrics.highlightTopOpacity),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom,
                        ),
                        lineWidth: Metrics.strokeWidth,
                    ),
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(design.colors.borderSubtle, lineWidth: Metrics.strokeWidth),
            )
            .shadow(
                color: design.shadows.soft.color,
                radius: design.shadows.soft.radius,
                x: design.shadows.soft.x,
                y: design.shadows.soft.y,
            )
    }
}

extension View {
    func umGlass(cornerRadius: CGFloat? = nil) -> some View {
        modifier(UMGlassModifier(
            cornerRadius: cornerRadius ?? DesignCorners.standard.md,
        ))
    }
}

// MARK: - Card Modifier

/// Card surface treatment with three style variants.
///
/// Usage:
/// ```
/// VStack { ... }
///     .umCard(.glass)
/// ```
struct UMCardModifier: ViewModifier {
    let style: Style

    @Environment(\.design)
    private var design

    enum Style {
        case glass
        case elevated
        case flat
    }

    private enum Metrics {
        static let borderWidth: CGFloat = 0.5
    }

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            content
                .umGlass(cornerRadius: design.corners.md)

        case .elevated:
            content
                .background(design.colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: design.corners.md))
                .overlay(
                    RoundedRectangle(cornerRadius: design.corners.md)
                        .stroke(design.colors.borderDefault, lineWidth: Metrics.borderWidth),
                )
                .shadow(
                    color: design.shadows.hard.color,
                    radius: design.shadows.hard.radius,
                    x: design.shadows.hard.x,
                    y: design.shadows.hard.y,
                )

        case .flat:
            content
                .background(design.colors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: design.corners.md))
        }
    }
}

extension View {
    func umCard(_ style: UMCardModifier.Style = .glass) -> some View {
        modifier(UMCardModifier(style: style))
    }
}

// MARK: - Section

/// Settings section with icon + uppercase label + content.
/// Replaces the repeated icon+headline+card pattern in preferences views.
///
/// Usage:
/// ```
/// UMSection("Alert Timing", icon: "bell.fill") {
///     // section content
/// }
/// ```
struct UMSection<Content: View>: View {
    let title: String
    let icon: String?
    @ViewBuilder
    let content: Content

    @Environment(\.design)
    private var design

    init(_ title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: design.spacing.lg) {
            HStack(spacing: design.spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundColor(design.colors.accent)
                        .font(design.fonts.body)
                        .fontWeight(.medium)
                }

                Text(title)
                    .font(design.fonts.headline)
                    .foregroundColor(design.colors.textPrimary)
            }

            content
        }
        .padding(design.spacing.lg)
        .umCard(.glass)
    }
}

// MARK: - Picker Style Modifier

/// Glass-styled modifier for native Picker controls.
///
/// Usage:
/// ```
/// Picker("Theme", selection: $mode) { ... }
///     .pickerStyle(.menu)
///     .umPickerStyle()
/// ```
struct UMPickerStyleModifier: ViewModifier {
    @Environment(\.design)
    private var design

    func body(content: Content) -> some View {
        content
            .font(design.fonts.callout)
            .foregroundColor(design.colors.textPrimary)
            .tint(design.colors.textPrimary)
    }
}

extension View {
    func umPickerStyle() -> some View {
        modifier(UMPickerStyleModifier())
    }
}
