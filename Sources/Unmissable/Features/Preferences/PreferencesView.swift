import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject
    var appState: AppState
    @Environment(\.customDesign)
    private var design
    @State
    private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Bar
            HStack {
                ForEach(0 ..< 4) { index in
                    Button(action: { selectedTab = index }) {
                        HStack(spacing: design.spacing.sm) {
                            Image(systemName: tabIcon(for: index))
                                .font(.system(size: 14, weight: .medium))

                            Text(tabTitle(for: index))
                                .font(design.fonts.callout)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(
                            selectedTab == index ? design.colors.textInverse : design.colors.textSecondary
                        )
                        .padding(.horizontal, design.spacing.lg)
                        .padding(.vertical, design.spacing.md)
                        .background(
                            selectedTab == index ? design.colors.accent : Color.clear
                        )
                        .cornerRadius(design.corners.medium)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(design.spacing.sm)
            .background(design.colors.backgroundSecondary)

            Rectangle()
                .fill(design.colors.divider)
                .frame(height: 1)

            // Tab Content
            Group {
                switch selectedTab {
                case 0:
                    GeneralPreferencesView()
                case 1:
                    CalendarPreferencesView()
                case 2:
                    AppearancePreferencesView()
                case 3:
                    ShortcutsPreferencesView()
                default:
                    GeneralPreferencesView()
                }
            }
            .environmentObject(appState.preferences)
            .customThemedEnvironment()
        }
        .background(design.colors.background)
        .frame(width: 650, height: 450)
    }

    private func tabIcon(for index: Int) -> String {
        switch index {
        case 0: "gear"
        case 1: "calendar"
        case 2: "paintbrush"
        case 3: "keyboard"
        default: "gear"
        }
    }

    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: "General"
        case 1: "Calendars"
        case 2: "Appearance"
        case 3: "Shortcuts"
        default: "General"
        }
    }
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @EnvironmentObject
    var preferences: PreferencesManager
    @Environment(\.customDesign)
    private var design

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("General Settings")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Configure alert timing and sync behavior")
                        .font(design.fonts.caption1)
                        .foregroundColor(design.colors.textSecondary)
                }

                alertTimingSection
                syncSettingsSection

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }

    // MARK: - Alert Timing

    private var alertTimingSection: some View {
        CustomCard(style: .standard) {
            VStack(alignment: .leading, spacing: design.spacing.lg) {
                HStack(spacing: design.spacing.sm) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(design.colors.accent)
                        .font(.system(size: 16, weight: .medium))

                    Text("Alert Timing")
                        .font(design.fonts.headline)
                        .foregroundColor(design.colors.textPrimary)
                }

                VStack(spacing: design.spacing.lg) {
                    defaultAlertRow
                    lengthBasedTimingRow

                    if preferences.useLengthBasedTiming {
                        lengthBasedTimingDetail
                    }
                }
            }
            .padding(design.spacing.lg)
        }
    }

    private var defaultAlertRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: design.spacing.xs) {
                Text("Default alert time")
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)

                Text("How early to show alerts before meetings")
                    .font(design.fonts.caption1)
                    .foregroundColor(design.colors.textSecondary)
            }

            Spacer()

            CustomPicker(
                "Minutes",
                selection: $preferences.defaultAlertMinutes,
                options: [
                    (1, "1 minute"),
                    (2, "2 minutes"),
                    (5, "5 minutes"),
                    (10, "10 minutes"),
                    (15, "15 minutes"),
                ]
            )
            .frame(width: 140)
        }
    }

    private var lengthBasedTimingRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: design.spacing.xs) {
                Text("Length-based timing")
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)

                Text("Use different alerts based on meeting duration")
                    .font(design.fonts.caption1)
                    .foregroundColor(design.colors.textSecondary)
            }

            Spacer()

            CustomToggle(isOn: $preferences.useLengthBasedTiming)
        }
    }

    private var lengthBasedTimingDetail: some View {
        CustomCard(style: .flat) {
            VStack(spacing: design.spacing.md) {
                HStack {
                    Text("Short meetings (<30 min)")
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)

                    Spacer()

                    CustomPicker(
                        "Short",
                        selection: $preferences.shortMeetingAlertMinutes,
                        options: [(1, "1 min"), (2, "2 min"), (5, "5 min")]
                    )
                    .frame(width: 80)
                }

                HStack {
                    Text("Medium meetings (30-60 min)")
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)

                    Spacer()

                    CustomPicker(
                        "Medium",
                        selection: $preferences.mediumMeetingAlertMinutes,
                        options: [(2, "2 min"), (5, "5 min"), (10, "10 min")]
                    )
                    .frame(width: 80)
                }

                HStack {
                    Text("Long meetings (>60 min)")
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)

                    Spacer()

                    CustomPicker(
                        "Long",
                        selection: $preferences.longMeetingAlertMinutes,
                        options: [(5, "5 min"), (10, "10 min"), (15, "15 min")]
                    )
                    .frame(width: 80)
                }
            }
            .padding(design.spacing.lg)
        }
    }

    // MARK: - Sync Settings

    private var syncSettingsSection: some View {
        CustomCard(style: .standard) {
            VStack(alignment: .leading, spacing: design.spacing.lg) {
                HStack(spacing: design.spacing.sm) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(design.colors.accent)
                        .font(.system(size: 16, weight: .medium))

                    Text("Sync Settings")
                        .font(design.fonts.headline)
                        .foregroundColor(design.colors.textPrimary)
                }

                VStack(spacing: design.spacing.lg) {
                    HStack {
                        VStack(alignment: .leading, spacing: design.spacing.xs) {
                            Text("Sync interval")
                                .font(design.fonts.callout)
                                .foregroundColor(design.colors.textPrimary)

                            Text("How often to check for calendar updates")
                                .font(design.fonts.caption1)
                                .foregroundColor(design.colors.textSecondary)
                        }

                        Spacer()

                        CustomPicker(
                            "Interval",
                            selection: $preferences.syncIntervalSeconds,
                            options: [
                                (15, "15 seconds"),
                                (30, "30 seconds"),
                                (60, "1 minute"),
                                (120, "2 minutes"),
                                (300, "5 minutes"),
                            ]
                        )
                        .frame(width: 120)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: design.spacing.xs) {
                            Text("All-day events")
                                .font(design.fonts.callout)
                                .foregroundColor(design.colors.textPrimary)

                            Text("Include all-day events in sync")
                                .font(design.fonts.caption1)
                                .foregroundColor(design.colors.textSecondary)
                        }

                        Spacer()

                        CustomToggle(isOn: $preferences.includeAllDayEvents)
                    }
                }
            }
            .padding(design.spacing.lg)
        }
    }
}

// MARK: - Shortcuts Preferences

struct ShortcutsPreferencesView: View {
    @EnvironmentObject
    var preferences: PreferencesManager
    @Environment(\.customDesign)
    private var design

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("Keyboard Shortcuts")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Global shortcuts work even when other apps are focused")
                        .font(design.fonts.caption1)
                        .foregroundColor(design.colors.textSecondary)
                }

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

    private func shortcutRow(
        title: String,
        subtitle: String,
        shortcut: String
    ) -> some View {
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
