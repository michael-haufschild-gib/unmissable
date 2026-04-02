import SwiftUI

// MARK: - Custom Button Components (No System Dependencies)

struct CustomButton: View {
    let title: String
    let icon: String?
    let style: CustomButtonStyle
    let action: () -> Void

    @Environment(\.customDesign)
    private var design
    @Environment(\.isEnabled)
    private var isEnabled
    @State
    private var isPressed = false

    init(
        _ title: String, icon: String? = nil, style: CustomButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: design.spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }

                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundView)
            .foregroundColor(textColor)
            .clipShape(RoundedRectangle(cornerRadius: buttonRadius))
            .overlay(
                RoundedRectangle(cornerRadius: buttonRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: buttonRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(style == .primary ? 0.15 : 0), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .shadow(
                color: style == .primary && isEnabled
                    ? design.colors.interactive.opacity(isPressed ? 0.2 : 0.35) : Color.clear,
                radius: isPressed ? 4 : 12,
                x: 0,
                y: isPressed ? 2 : 4
            )
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onPress {
            isPressed = $0
        }
        .disabled(!isEnabled)
    }

    private var buttonRadius: CGFloat {
        switch style {
        case .primary, .destructive:
            design.corners.large
        default:
            design.corners.medium
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .primary, .secondary, .destructive:
            design.spacing.lg
        case .minimal:
            design.spacing.md
        case .icon:
            design.spacing.sm
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .primary, .secondary, .destructive:
            design.spacing.md
        case .minimal:
            design.spacing.sm
        case .icon:
            design.spacing.sm
        }
    }

    /// Background color for non-primary styles or disabled state.
    /// Primary+enabled uses `backgroundView` with a brightness modifier instead.
    private var backgroundColor: Color {
        if !isEnabled {
            return design.colors.backgroundButton.opacity(0.5)
        }

        switch style {
        case .primary:
            // Primary+enabled is handled by backgroundView; this branch exists
            // only for exhaustiveness. Disabled primary returns at the guard above.
            return design.colors.interactive
        case .secondary:
            return isPressed ? design.colors.backgroundSecondary : design.colors.backgroundButton
        case .destructive:
            return isPressed ? design.colors.error.opacity(0.8) : design.colors.error
        case .minimal:
            return isPressed ? design.colors.backgroundSecondary : Color.clear
        case .icon:
            return isPressed
                ? design.colors.interactive.opacity(0.2) : design.colors.interactive.opacity(0.1)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if style == .primary, isEnabled {
            design.colors.interactive
                .brightness(isPressed ? -0.1 : 0.0)
        } else {
            backgroundColor
        }
    }

    private var textColor: Color {
        if !isEnabled {
            return design.colors.interactiveDisabled
        }

        switch style {
        case .primary:
            return design.colors.textInverse
        case .secondary:
            return design.colors.interactive
        case .destructive:
            return design.colors.textInverse
        case .minimal:
            return design.colors.interactive
        case .icon:
            return design.colors.interactive
        }
    }

    private var borderColor: Color {
        if !isEnabled {
            return design.colors.border
        }

        switch style {
        case .primary, .destructive:
            return Color.clear
        case .secondary:
            return design.colors.interactive
        case .minimal:
            return Color.clear
        case .icon:
            return Color.clear
        }
    }

    private var borderWidth: CGFloat {
        switch style {
        case .secondary:
            1.5
        default:
            0
        }
    }
}

enum CustomButtonStyle {
    case primary
    case secondary
    case destructive
    case minimal
    case icon
}

// MARK: - Custom Toggle Style

struct CustomToggleStyle: ToggleStyle {
    @Environment(\.customDesign)
    private var design
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Spacer()

            HStack(spacing: 0) {
                if !configuration.isOn {
                    Spacer()
                }

                Circle()
                    .fill(thumbColor)
                    .frame(width: 22, height: 22)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)

                if configuration.isOn {
                    Spacer()
                }
            }
            .padding(.horizontal, 3)
            .frame(width: 44, height: 26)
            .background(
                Capsule()
                    .fill(trackColor(isOn: configuration.isOn))
                    .shadow(
                        color: configuration.isOn ? design.colors.accent.opacity(0.3) : Color.clear,
                        radius: 6
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }

    private func trackColor(isOn: Bool) -> Color {
        if !isEnabled {
            return design.colors.backgroundSecondary
        }
        return isOn ? design.colors.accent : Color.gray.opacity(0.4)
    }

    private var thumbColor: Color {
        if !isEnabled {
            return design.colors.interactiveDisabled
        }
        return Color.white
    }
}

// MARK: - Custom Toggle Convenience

struct CustomToggle: View {
    @Binding
    var isOn: Bool
    let label: String?

    init(_ label: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            if let label {
                Text(label)
            }
        }
        .toggleStyle(CustomToggleStyle())
    }
}

// MARK: - Custom Status Indicator

struct CustomStatusIndicator: View {
    let status: Status
    let size: CGFloat

    @Environment(\.customDesign)
    private var design

    init(status: Status, size: CGFloat = 10) {
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
        case .connected:
            design.colors.success
        case .connecting:
            design.colors.warning
        case .disconnected:
            design.colors.textTertiary
        case .error:
            design.colors.error
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(statusColor.opacity(0.3), lineWidth: 2)
                .frame(width: size + 4, height: size + 4)
                .scaleEffect(status == .connecting ? 1.3 : 1.0)
                .opacity(status == .connecting ? 0.5 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: status == .connecting
                )

            Circle()
                .fill(statusColor)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Helper Extensions

extension View {
    func onPress(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(PressedModifier(action: action))
    }
}

struct PressedModifier: ViewModifier {
    let action: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(
                minimumDuration: 0, maximumDistance: .infinity, pressing: action, perform: {}
            )
    }
}
