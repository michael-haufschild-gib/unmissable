import SwiftUI

struct AppearancePreferencesView: View {
    @EnvironmentObject var preferences: PreferencesManager
    @Environment(\.customDesign) private var design
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("Appearance")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Customize the visual appearance and behavior")
                        .font(design.fonts.caption1)
                        .foregroundColor(design.colors.textSecondary)
                }

                // Theme section
                CustomCard(style: .standard) {
                    VStack(alignment: .leading, spacing: design.spacing.lg) {
                        HStack(spacing: design.spacing.sm) {
                            Image(systemName: "paintbrush.fill")
                                .foregroundColor(design.colors.accent)
                                .font(.system(size: 16, weight: .medium))

                            Text("Theme")
                                .font(design.fonts.headline)
                                .foregroundColor(design.colors.textPrimary)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: design.spacing.xs) {
                                Text("Appearance")
                                    .font(design.fonts.callout)
                                    .foregroundColor(design.colors.textPrimary)

                                Text("Choose light, dark, or follow system setting")
                                    .font(design.fonts.caption1)
                                    .foregroundColor(design.colors.textSecondary)
                            }

                            Spacer()

                            CustomPicker(
                                "Theme",
                                selection: $preferences.appearanceTheme,
                                options: AppTheme.allCases.map { ($0, $0.displayName) }
                            )
                            .frame(width: 160)
                        }
                    }
                    .padding(design.spacing.lg)
                }

                // Menu Bar Display section
                CustomCard(style: .standard) {
                    VStack(alignment: .leading, spacing: design.spacing.lg) {
                        HStack(spacing: design.spacing.sm) {
                            Image(systemName: "menubar.rectangle")
                                .foregroundColor(design.colors.accent)
                                .font(.system(size: 16, weight: .medium))

                            Text("Menu Bar Display")
                                .font(design.fonts.headline)
                                .foregroundColor(design.colors.textPrimary)
                        }

                        VStack(spacing: design.spacing.lg) {
                            HStack {
                                VStack(alignment: .leading, spacing: design.spacing.xs) {
                                    Text("Display mode")
                                        .font(design.fonts.callout)
                                        .foregroundColor(design.colors.textPrimary)

                                    Text("Choose what to show in the menu bar")
                                        .font(design.fonts.caption1)
                                        .foregroundColor(design.colors.textSecondary)
                                }

                                Spacer()

                                CustomPicker(
                                    "Mode",
                                    selection: $preferences.menuBarDisplayMode,
                                    options: MenuBarDisplayMode.allCases.map { ($0, $0.displayName) }
                                )
                                .frame(width: 140)
                            }
                        }
                    }
                    .padding(design.spacing.lg)
                }

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }
}

// MARK: - Shortcuts Preferences

struct ShortcutsPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesManager
    @Environment(\.customDesign) private var design

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("Keyboard Shortcuts")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Global shortcuts work even when other apps are focused")
                        .font(design.fonts.caption1)
                        .foregroundColor(design.colors.textSecondary)
                }

                // Shortcuts section
                CustomCard(style: .standard) {
                    VStack(alignment: .leading, spacing: design.spacing.lg) {
                        HStack(spacing: design.spacing.sm) {
                            Image(systemName: "keyboard")
                                .foregroundColor(design.colors.accent)
                                .font(.system(size: 16, weight: .medium))

                            Text("Global Shortcuts")
                                .font(design.fonts.headline)
                                .foregroundColor(design.colors.textPrimary)
                        }

                        VStack(spacing: design.spacing.lg) {
                            shortcutRow(
                                title: "Dismiss overlay",
                                subtitle: "Close the current meeting alert",
                                shortcut: "⌘⎋"
                            )

                            shortcutRow(
                                title: "Join meeting",
                                subtitle: "Quickly join the current meeting",
                                shortcut: "⌘⏎"
                            )
                        }
                    }
                    .padding(design.spacing.lg)
                }

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }

    private func shortcutRow(title: String, subtitle: String, shortcut: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: design.spacing.xs) {
                Text(title)
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)

                Text(subtitle)
                    .font(design.fonts.caption1)
                    .foregroundColor(design.colors.textSecondary)
            }

            Spacer()

            Text(shortcut)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(design.colors.textPrimary)
                .padding(.horizontal, design.spacing.md)
                .padding(.vertical, design.spacing.sm)
                .background(design.colors.backgroundSecondary)
                .cornerRadius(design.corners.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: design.corners.medium)
                        .stroke(design.colors.border, lineWidth: 1)
                )
        }
    }
}
