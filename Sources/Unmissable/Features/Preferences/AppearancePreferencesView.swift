import SwiftUI

struct AppearancePreferencesView: View {
    @EnvironmentObject
    var preferences: PreferencesManager
    @Environment(\.design)
    private var design
    @EnvironmentObject
    private var themeManager: ThemeManager

    private static let themePickerWidth: CGFloat = 160
    private static let menuBarPickerWidth: CGFloat = 140
    private static let swatchSize: CGFloat = 24
    private static let swatchRingSize: CGFloat = 30
    private static let swatchRingOpacity: Double = 0.3
    private static let swatchOuterRingOpacity: Double = 0.5
    private static let swatchStrokeWidth: CGFloat = 2
    private static let swatchOuterStrokeWidth: CGFloat = 1
    private static let swatchSelectedScale: CGFloat = 1.1
    private static let swatchUnselectedScale: CGFloat = 1.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("Appearance")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Customize the visual appearance and behavior")
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textSecondary)
                }

                // Theme mode section
                UMSection("Theme", icon: "paintbrush.fill") {
                    VStack(alignment: .leading, spacing: design.spacing.lg) {
                        // Theme mode picker
                        HStack {
                            VStack(alignment: .leading, spacing: design.spacing.xs) {
                                Text("Mode")
                                    .font(design.fonts.callout)
                                    .foregroundColor(design.colors.textPrimary)

                                Text("Choose a theme mode for the app")
                                    .font(design.fonts.caption)
                                    .foregroundColor(design.colors.textSecondary)
                            }

                            Spacer()

                            Picker("Theme", selection: preferences.themeModeBinding) {
                                ForEach(ThemeMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .umPickerStyle()
                            .frame(width: Self.themePickerWidth)
                        }

                        // Accent color picker
                        VStack(alignment: .leading, spacing: design.spacing.md) {
                            Text("Accent Color")
                                .font(design.fonts.callout)
                                .foregroundColor(design.colors.textPrimary)

                            HStack(spacing: design.spacing.md) {
                                ForEach(AccentColor.allCases, id: \.self) { accent in
                                    accentSwatch(accent)
                                }
                            }
                        }
                    }
                }

                // Menu Bar Display section
                UMSection("Menu Bar Display", icon: "menubar.rectangle") {
                    HStack {
                        VStack(alignment: .leading, spacing: design.spacing.xs) {
                            Text("Display mode")
                                .font(design.fonts.callout)
                                .foregroundColor(design.colors.textPrimary)

                            Text("Choose what to show in the menu bar")
                                .font(design.fonts.caption)
                                .foregroundColor(design.colors.textSecondary)
                        }

                        Spacer()

                        Picker("Mode", selection: preferences.menuBarDisplayModeBinding) {
                            ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .umPickerStyle()
                        .frame(width: Self.menuBarPickerWidth)
                    }
                }

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }

    // MARK: - Accent Color Swatch

    private func accentSwatch(_ accent: AccentColor) -> some View {
        Button {
            preferences.setAccentColor(accent)
        } label: {
            Circle()
                .fill(accent.color)
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                .overlay(
                    Circle()
                        .stroke(
                            design.colors.textPrimary.opacity(Self.swatchRingOpacity),
                            lineWidth: preferences.accentColor == accent ? Self.swatchStrokeWidth : 0,
                        ),
                )
                .overlay(
                    Circle()
                        .stroke(
                            accent.color.opacity(Self.swatchOuterRingOpacity),
                            lineWidth: preferences.accentColor == accent ? Self.swatchOuterStrokeWidth : 0,
                        )
                        .frame(width: Self.swatchRingSize, height: Self.swatchRingSize),
                )
                .scaleEffect(
                    preferences.accentColor == accent ? Self.swatchSelectedScale : Self.swatchUnselectedScale,
                )
                .animation(DesignAnimations.press, value: preferences.accentColor == accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accent.displayName) accent color")
        .accessibilityAddTraits(preferences.accentColor == accent ? .isSelected : [])
    }
}
