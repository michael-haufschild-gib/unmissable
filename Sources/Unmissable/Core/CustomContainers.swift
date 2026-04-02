import SwiftUI

// MARK: - Custom Card Container

struct CustomCard<Content: View>: View {
    let content: Content
    let style: CardStyle

    @Environment(\.customDesign)
    private var design

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
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(innerHighlightOpacity),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
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

    private var innerHighlightOpacity: Double {
        switch style {
        case .standard, .elevated:
            0.06
        case .flat:
            0
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .standard, .elevated:
            design.colors.backgroundCard
        case .flat:
            design.colors.backgroundTertiary
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
    @Binding
    var selection: SelectionValue
    let options: [(SelectionValue, String)]

    @Environment(\.customDesign)
    private var design
    @State
    private var isExpanded = false

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
                                selection == option.0
                                    ? design.colors.interactive.opacity(0.1) : Color.clear
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
