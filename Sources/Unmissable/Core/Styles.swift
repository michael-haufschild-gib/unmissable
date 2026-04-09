import SwiftUI

// MARK: - Button Style

/// Design-system button style applied to native SwiftUI Button.
///
/// Usage:
/// ```
/// Button("Join") { ... }
///     .buttonStyle(UMButtonStyle(.primary))
/// ```
struct UMButtonStyle: ButtonStyle {
    let variant: Variant
    let size: Size

    @Environment(\.design)
    private var design
    @Environment(\.isEnabled)
    private var isEnabled

    init(_ variant: Variant = .primary, size: Size = .md) {
        self.variant = variant
        self.size = size
    }

    enum Variant {
        case primary
        case secondary
        case ghost
        case danger
    }

    enum Size {
        case sm
        case md
        case lg
        case icon
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(fontSize)
            .fontWeight(.medium)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: minHeight)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: borderLineWidth),
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? Metrics.pressedScale : Metrics.fullScale)
            .opacity(isEnabled ? Metrics.fullOpacity : Metrics.disabledOpacity)
            .animation(DesignAnimations.press, value: configuration.isPressed)
    }

    // MARK: - Metrics

    private enum Metrics {
        static let pressedScale: CGFloat = 0.98
        static let fullScale: CGFloat = 1.0
        static let fullOpacity: Double = 1.0
        static let disabledOpacity: Double = 0.5
        static let borderWidth: CGFloat = 1
        static let noBorderWidth: CGFloat = 0
        static let dangerBorderOpacity: Double = 0.5
        static let minHeightSm: CGFloat = 28
        static let minHeightMd: CGFloat = 36
        static let minHeightLg: CGFloat = 44
    }

    // MARK: - Computed Properties

    private var foregroundColor: Color {
        guard isEnabled else { return design.colors.textMuted }
        switch variant {
        case .primary: return design.colors.accent
        case .secondary: return design.colors.textSecondary
        case .ghost: return design.colors.textSecondary
        case .danger: return design.colors.error
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return Color.clear }
        if isPressed {
            switch variant {
            case .primary: return design.colors.accentSubtle
            case .secondary: return design.colors.active
            case .ghost: return design.colors.active
            case .danger: return design.colors.errorSubtle
            }
        }
        return Color.clear
    }

    private var borderColor: Color {
        guard isEnabled else { return design.colors.borderSubtle }
        switch variant {
        case .primary: return design.colors.accent
        case .secondary: return design.colors.borderDefault
        case .ghost: return Color.clear
        case .danger: return design.colors.error.opacity(Metrics.dangerBorderOpacity)
        }
    }

    private var hasBorder: Bool {
        switch variant {
        case .primary, .secondary, .danger: true
        case .ghost: false
        }
    }

    private var borderLineWidth: CGFloat {
        hasBorder ? Metrics.borderWidth : Metrics.noBorderWidth
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .sm: design.corners.sm
        case .md, .icon: design.corners.md
        case .lg: design.corners.lg
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .sm: design.spacing.sm
        case .md: design.spacing.md
        case .lg: design.spacing.lg
        case .icon: design.spacing.sm
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .sm: design.spacing.xs
        case .md: design.spacing.sm
        case .lg: design.spacing.md
        case .icon: design.spacing.sm
        }
    }

    private var minHeight: CGFloat {
        switch size {
        case .sm: Metrics.minHeightSm
        case .md: Metrics.minHeightMd
        case .lg: Metrics.minHeightLg
        case .icon: Metrics.minHeightMd
        }
    }

    private var fontSize: Font {
        switch size {
        case .sm: design.fonts.caption
        case .md: design.fonts.callout
        case .lg: design.fonts.body
        case .icon: design.fonts.callout
        }
    }
}

// MARK: - Toggle Style

/// Design-system toggle style with spring-animated thumb.
///
/// Usage:
/// ```
/// Toggle("Option", isOn: $value)
///     .toggleStyle(UMToggleStyle())
/// ```
struct UMToggleStyle: ToggleStyle {
    @Environment(\.design)
    private var design
    @Environment(\.isEnabled)
    private var isEnabled

    private enum Metrics {
        static let thumbDiameter: CGFloat = 20
        static let trackWidth: CGFloat = 44
        static let trackHeight: CGFloat = 26
        static let trackPadding: CGFloat = 3
        static let thumbShadowRadius: CGFloat = 2
        static let thumbShadowY: CGFloat = 1
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Spacer()

            HStack(spacing: 0) {
                if configuration.isOn {
                    Spacer()
                }

                Circle()
                    .fill(isEnabled ? Color.white : design.colors.textMuted)
                    .frame(width: Metrics.thumbDiameter, height: Metrics.thumbDiameter)
                    .shadow(
                        color: design.shadows.soft.color,
                        radius: Metrics.thumbShadowRadius,
                        y: Metrics.thumbShadowY,
                    )

                if !configuration.isOn {
                    Spacer()
                }
            }
            .padding(.horizontal, Metrics.trackPadding)
            .frame(width: Metrics.trackWidth, height: Metrics.trackHeight)
            .background(
                Capsule()
                    .fill(trackColor(isOn: configuration.isOn)),
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(DesignAnimations.press) {
                    configuration.isOn.toggle()
                }
            }
        }
    }

    private func trackColor(isOn: Bool) -> Color {
        if !isEnabled {
            return design.colors.surface
        }
        return isOn ? design.colors.accent : design.colors.surface
    }
}

// MARK: - Status Indicator

struct UMStatusIndicator: View {
    let status: Status
    let size: CGFloat

    @Environment(\.design)
    private var design

    private enum Metrics {
        static let defaultSize: CGFloat = 10
        static let ringExpansion: CGFloat = 4
        static let ringStrokeWidth: CGFloat = 2
        static let ringOpacity: Double = 0.3
        static let connectingScale: CGFloat = 1.3
        static let connectingOpacity: Double = 0.5
        static let idleScale: CGFloat = 1.0
        static let idleOpacity: Double = 1.0
    }

    init(_ status: Status, size: CGFloat = Metrics.defaultSize) {
        self.status = status
        self.size = size
    }

    enum Status {
        case connected
        case connecting
        case disconnected
        case error
    }

    private var statusColor: Color {
        switch status {
        case .connected: design.colors.success
        case .connecting: design.colors.warning
        case .disconnected: design.colors.textTertiary
        case .error: design.colors.error
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(statusColor.opacity(Metrics.ringOpacity), lineWidth: Metrics.ringStrokeWidth)
                .frame(
                    width: size + Metrics.ringExpansion,
                    height: size + Metrics.ringExpansion,
                )
                .scaleEffect(status == .connecting ? Metrics.connectingScale : Metrics.idleScale)
                .opacity(status == .connecting ? Metrics.connectingOpacity : Metrics.idleOpacity)
                .animation(
                    DesignAnimations.ambient.repeatForever(autoreverses: true),
                    value: status == .connecting,
                )

            Circle()
                .fill(statusColor)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Keycap

/// Individual keyboard key rendered as a physical keycap.
/// Used to display keyboard shortcuts with macOS-native visual treatment.
///
/// Usage:
/// ```
/// HStack(spacing: design.spacing.xs) {
///     UMKeyCap(label: "⌘")
///     UMKeyCap(label: "Esc")
/// }
/// ```
struct UMKeyCap: View {
    let label: String

    @Environment(\.design)
    private var design

    private enum Metrics {
        static let minWidth: CGFloat = 28
        static let height: CGFloat = 26
        static let highlightDivisor: CGFloat = 2
        static let borderWidth: CGFloat = 0.5
        static let bottomBorderWidth: CGFloat = 1.5
        static let topHighlightOpacity: Double = 0.08
    }

    var body: some View {
        Text(label)
            .font(design.fonts.caption)
            .fontWeight(.medium)
            .foregroundColor(design.colors.textPrimary)
            .frame(minWidth: Metrics.minWidth, minHeight: Metrics.height)
            .padding(.horizontal, design.spacing.sm)
            .background(design.colors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: design.corners.sm))
            .overlay(
                RoundedRectangle(cornerRadius: design.corners.sm)
                    .stroke(design.colors.borderDefault, lineWidth: Metrics.borderWidth),
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: design.corners.sm)
                    .fill(Color.white.opacity(Metrics.topHighlightOpacity))
                    .frame(height: Metrics.height / Metrics.highlightDivisor)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom,
                        ),
                    )
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(design.colors.borderStrong)
                    .frame(height: Metrics.bottomBorderWidth)
                    .clipShape(
                        .rect(
                            bottomLeadingRadius: design.corners.sm,
                            bottomTrailingRadius: design.corners.sm,
                        ),
                    )
            }
    }
}

/// Renders a full keyboard shortcut as a row of keycaps.
///
/// Usage:
/// ```
/// UMShortcutDisplay(labels: ["⌘", "Esc"])
/// ```
struct UMShortcutDisplay: View {
    let labels: [String]

    @Environment(\.design)
    private var design

    var body: some View {
        HStack(spacing: design.spacing.xs) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                UMKeyCap(label: label)
            }
        }
    }
}

// MARK: - Badge

/// Small pill label for status or category tags.
struct UMBadge: View {
    let text: String
    let variant: Variant

    @Environment(\.design)
    private var design

    init(_ text: String, variant: Variant = .accent) {
        self.text = text
        self.variant = variant
    }

    enum Variant {
        case accent
        case success
        case warning
        case error
        case neutral
    }

    private var foreground: Color {
        switch variant {
        case .accent: design.colors.accent
        case .success: design.colors.success
        case .warning: design.colors.warning
        case .error: design.colors.error
        case .neutral: design.colors.textSecondary
        }
    }

    private var background: Color {
        switch variant {
        case .accent: design.colors.accentSubtle
        case .success: design.colors.successSubtle
        case .warning: design.colors.warningSubtle
        case .error: design.colors.errorSubtle
        case .neutral: design.colors.hover
        }
    }

    var body: some View {
        Text(text)
            .font(design.fonts.caption)
            .fontWeight(.medium)
            .foregroundColor(foreground)
            .padding(.horizontal, design.spacing.sm)
            .padding(.vertical, design.spacing.xs)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: design.corners.sm))
    }
}
