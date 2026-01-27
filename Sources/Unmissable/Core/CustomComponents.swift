import SwiftUI

// MARK: - Custom Button Components (No System Dependencies)

struct CustomButton: View {
    let title: String
    let icon: String?
    let style: CustomButtonStyle
    let action: () -> Void

    @Environment(\.customDesign) private var design
    @Environment(\.isEnabled) private var isEnabled
    @State private var isPressed = false

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
                        .font(.system(size: 14, weight: .medium))
                }

                Text(title)
                    .font(design.fonts.callout)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundView)
            .foregroundColor(textColor)
            .cornerRadius(design.corners.medium)
            .overlay(
                RoundedRectangle(cornerRadius: design.corners.medium)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .shadow(
                color: style == .primary && isEnabled
                    ? design.colors.interactive.opacity(0.3) : Color.clear,
                radius: isPressed ? 2 : 8,
                x: 0,
                y: isPressed ? 1 : 3
            )
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onPress {
            isPressed = $0
        }
        .disabled(!isEnabled)
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

    private var backgroundColor: Color {
        if !isEnabled {
            return design.colors.backgroundButton.opacity(0.5)
        }

        switch style {
        case .primary:
            // Use a subtle gradient effect inspired by AI Wave
            return isPressed ? design.colors.interactivePressed : design.colors.interactive
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
            // AI Wave inspired gradient for primary buttons
            LinearGradient(
                gradient: Gradient(colors: [
                    design.colors.interactive,
                    design.colors.accentSecondary,
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .brightness(isPressed ? -0.2 : 0.0)
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
    @Environment(\.customDesign) private var design
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Spacer()

            // Toggle track and thumb using layout-based positioning
            HStack(spacing: 0) {
                if !configuration.isOn {
                    Spacer()
                }

                Circle()
                    .fill(thumbColor)
                    .frame(width: 24, height: 24)
                    .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)

                if configuration.isOn {
                    Spacer()
                }
            }
            .padding(.horizontal, 2)
            .frame(width: 48, height: 28)
            .background(
                Capsule()
                    .fill(trackColor(isOn: configuration.isOn))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
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
    @Binding var isOn: Bool
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

    @Environment(\.customDesign) private var design

    init(status: Status, size: CGFloat = 10) {
        self.status = status
        self.size = size
    }

    enum Status {
        case connected
        case connecting
        case disconnected
        case error

        var color: Color {
            switch self {
            case .connected:
                Color(red: 0.2, green: 0.8, blue: 0.4) // Success green
            case .connecting:
                Color(red: 1.0, green: 0.7, blue: 0.1) // Warning orange
            case .disconnected:
                Color(red: 0.6, green: 0.6, blue: 0.65) // Neutral gray
            case .error:
                Color(red: 1.0, green: 0.35, blue: 0.3) // Error red
            }
        }
    }

    var body: some View {
        ZStack {
            // Outer ring (pulse effect for connecting)
            Circle()
                .stroke(status.color.opacity(0.3), lineWidth: 2)
                .frame(width: size + 4, height: size + 4)
                .scaleEffect(status == .connecting ? 1.3 : 1.0)
                .opacity(status == .connecting ? 0.5 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: status == .connecting
                )

            // Inner dot
            Circle()
                .fill(status.color)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Custom Card Container

struct CustomCard<Content: View>: View {
    let content: Content
    let style: CardStyle

    @Environment(\.customDesign) private var design

    init(style: CardStyle = .standard, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    enum CardStyle {
        case standard
        case elevated
        case flat
    }

    var body: some View {
        content
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowOffset
            )
    }

    private var backgroundColor: Color {
        switch style {
        case .standard:
            design.colors.backgroundCard
        case .elevated:
            design.colors.backgroundCard
        case .flat:
            design.colors.backgroundTertiary // Use tertiary for better contrast
        }
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .standard, .flat:
            design.corners.medium
        case .elevated:
            design.corners.large
        }
    }

    private var borderColor: Color {
        switch style {
        case .standard, .elevated:
            design.colors.border
        case .flat:
            Color.clear
        }
    }

    private var borderWidth: CGFloat {
        switch style {
        case .standard, .elevated:
            0.5
        case .flat:
            0
        }
    }

    private var shadowColor: Color {
        switch style {
        case .elevated:
            design.shadows.color
        default:
            Color.clear
        }
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .elevated:
            design.shadows.radius
        default:
            0
        }
    }

    private var shadowOffset: CGFloat {
        switch style {
        case .elevated:
            design.shadows.offset.height
        default:
            0
        }
    }
}

// MARK: - Custom Picker

struct CustomPicker<SelectionValue: Hashable>: View {
    let title: String
    @Binding var selection: SelectionValue
    let options: [(SelectionValue, String)]

    @Environment(\.customDesign) private var design
    @State private var isExpanded = false

    init(_ title: String, selection: Binding<SelectionValue>, options: [(SelectionValue, String)]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: design.spacing.xs) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(selectedOptionText)
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(design.colors.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.horizontal, design.spacing.md)
                .padding(.vertical, design.spacing.md)
                .background(design.colors.backgroundButton)
                .cornerRadius(design.corners.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: design.corners.medium)
                        .stroke(design.colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button(action: {
                            selection = option.0
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = false
                            }
                        }) {
                            HStack {
                                Text(option.1)
                                    .font(design.fonts.callout)
                                    .foregroundColor(design.colors.textPrimary)

                                Spacer()

                                if selection == option.0 {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(design.colors.interactive)
                                }
                            }
                            .padding(.horizontal, design.spacing.md)
                            .padding(.vertical, design.spacing.sm)
                            .background(
                                selection == option.0 ? design.colors.interactive.opacity(0.1) : Color.clear
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        if index < options.count - 1 {
                            Rectangle()
                                .fill(design.colors.divider)
                                .frame(height: 1)
                                .padding(.horizontal, design.spacing.md)
                        }
                    }
                }
                .background(design.colors.backgroundCard)
                .cornerRadius(design.corners.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: design.corners.medium)
                        .stroke(design.colors.border, lineWidth: 1)
                )
                .shadow(
                    color: design.shadows.color, radius: design.shadows.radius, x: 0,
                    y: design.shadows.offset.height
                )
            }
        }
    }

    private var selectedOptionText: String {
        options.first { $0.0 == selection }?.1 ?? "Select"
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
