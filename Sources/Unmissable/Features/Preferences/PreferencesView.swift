import SwiftUI

private enum PreferencesTab: Int, CaseIterable {
    case general
    case calendars
    case appearance
    case shortcuts

    var title: String {
        switch self {
        case .general: "General"
        case .calendars: "Calendars"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .calendars: "calendar"
        case .appearance: "paintbrush"
        case .shortcuts: "keyboard"
        }
    }
}

struct PreferencesView: View {
    @Environment(AppState.self)
    var appState
    @Environment(\.design)
    private var design
    @State
    private var selectedTab: PreferencesTab = .general

    private static let windowWidth: CGFloat = 650
    private static let windowHeight: CGFloat = 450
    private static let headerBorderHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Bar
            HStack {
                ForEach(PreferencesTab.allCases, id: \.rawValue) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: design.spacing.sm) {
                            Image(systemName: tab.icon)
                                .font(design.fonts.body)
                                .fontWeight(.medium)

                            Text(tab.title)
                                .font(design.fonts.callout)
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(
                        UMButtonStyle(selectedTab == tab ? .primary : .ghost),
                    )
                }
            }
            .padding(design.spacing.sm)
            .background(design.colors.surface)

            Rectangle()
                .fill(design.colors.borderSubtle)
                .frame(height: Self.headerBorderHeight)

            // Tab Content
            Group {
                switch selectedTab {
                case .general:
                    GeneralPreferencesView()
                case .calendars:
                    CalendarPreferencesView()
                case .appearance:
                    AppearancePreferencesView()
                case .shortcuts:
                    ShortcutsPreferencesView()
                }
            }
            .environment(appState.preferences)
        }
        .background(design.colors.background)
        .frame(width: Self.windowWidth, height: Self.windowHeight)
    }
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @Environment(PreferencesManager.self)
    var preferences
    @Environment(\.design)
    private var design

    private static let defaultAlertPickerWidth: CGFloat = 160
    private static let lengthBasedPickerWidth: CGFloat = 140
    private static let syncPickerWidth: CGFloat = 140
    private static let displayPickerWidth: CGFloat = 200

    // Picker tag values (minutes)
    private static let alertTag1Min = 1
    private static let alertTag2Min = 2
    private static let alertTag5Min = 5
    private static let alertTag10Min = 10
    private static let alertTag15Min = 15

    // Sync interval tag values (seconds)
    private static let syncTag30Sec = 30
    private static let syncTag1Min = 60
    private static let syncTag2Min = 120
    private static let syncTag5Min = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("General Settings")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Configure alert timing and sync behavior")
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textSecondary)
                }

                alertTimingSection
                displaySelectionSection
                smartAlertSection
                syncSettingsSection
                startupSection

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }

    // MARK: - Alert Timing

    private var alertTimingSection: some View {
        UMSection("Alert Timing", icon: "bell.fill") {
            VStack(spacing: design.spacing.lg) {
                defaultAlertRow
                lengthBasedTimingRow

                if preferences.useLengthBasedTiming {
                    lengthBasedTimingDetail
                }
            }
        }
    }

    private var defaultAlertRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: design.spacing.xs) {
                Text("Default alert time")
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)

                Text("How early to show alerts before meetings")
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textSecondary)
            }

            Spacer()

            Picker("Minutes", selection: preferences.defaultAlertMinutesBinding) {
                Text("1 minute").tag(Self.alertTag1Min)
                Text("2 minutes").tag(Self.alertTag2Min)
                Text("5 minutes").tag(Self.alertTag5Min)
                Text("10 minutes").tag(Self.alertTag10Min)
                Text("15 minutes").tag(Self.alertTag15Min)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .umPickerStyle()
            .frame(width: Self.defaultAlertPickerWidth)
        }
    }

    private var lengthBasedTimingRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: design.spacing.xs) {
                Text("Length-based timing")
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)

                Text("Use different alerts based on meeting duration")
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textSecondary)
            }

            Spacer()

            Toggle(isOn: preferences.useLengthBasedTimingBinding) {}
                .toggleStyle(UMToggleStyle())
                .labelsHidden()
                .accessibilityLabel("Use length-based timing")
        }
    }

    private var lengthBasedTimingDetail: some View {
        VStack(spacing: design.spacing.md) {
            HStack {
                Text("Short meetings (<30 min)")
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)

                Spacer()

                Picker("Short", selection: preferences.shortMeetingAlertMinutesBinding) {
                    Text("1 min").tag(Self.alertTag1Min)
                    Text("2 min").tag(Self.alertTag2Min)
                    Text("5 min").tag(Self.alertTag5Min)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .umPickerStyle()
                .frame(width: Self.lengthBasedPickerWidth)
            }

            HStack {
                Text("Medium meetings (30-60 min)")
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)

                Spacer()

                Picker("Medium", selection: preferences.mediumMeetingAlertMinutesBinding) {
                    Text("2 min").tag(Self.alertTag2Min)
                    Text("5 min").tag(Self.alertTag5Min)
                    Text("10 min").tag(Self.alertTag10Min)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .umPickerStyle()
                .frame(width: Self.lengthBasedPickerWidth)
            }

            HStack {
                Text("Long meetings (>60 min)")
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)

                Spacer()

                Picker("Long", selection: preferences.longMeetingAlertMinutesBinding) {
                    Text("5 min").tag(Self.alertTag5Min)
                    Text("10 min").tag(Self.alertTag10Min)
                    Text("15 min").tag(Self.alertTag15Min)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .umPickerStyle()
                .frame(width: Self.lengthBasedPickerWidth)
            }
        }
        .padding(design.spacing.lg)
        .umCard(.flat)
    }

    // MARK: - Display Selection

    private var displaySelectionSection: some View {
        UMSection("Display Selection", icon: "display") {
            VStack(spacing: design.spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: design.spacing.xs) {
                        Text("Show overlay on")
                            .font(design.fonts.callout)
                            .foregroundColor(design.colors.textPrimary)

                        Text("Choose which displays show the meeting overlay")
                            .font(design.fonts.caption)
                            .foregroundColor(design.colors.textSecondary)
                    }

                    Spacer()

                    Picker("Displays", selection: preferences.displaySelectionModeBinding) {
                        ForEach(DisplaySelectionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .umPickerStyle()
                    .frame(width: Self.displayPickerWidth)
                }

                if preferences.displaySelectionMode == .selected {
                    DisplayArrangementView()
                        .umCard(.flat)
                }
            }
        }
    }

    // MARK: - Smart Alerts

    private var smartAlertSection: some View {
        UMSection("Smart Alerts", icon: "brain") {
            HStack {
                VStack(alignment: .leading, spacing: design.spacing.xs) {
                    Text("Suppress when app is open")
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Skip the alert when the meeting app is already in the foreground")
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textSecondary)
                }

                Spacer()

                Toggle(isOn: preferences.smartSuppressionBinding) {}
                    .toggleStyle(UMToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel("Suppress alert when meeting app is open")
            }
        }
    }

    // MARK: - Sync Settings

    private var syncSettingsSection: some View {
        UMSection("Sync Settings", icon: "arrow.triangle.2.circlepath") {
            VStack(spacing: design.spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: design.spacing.xs) {
                        Text("Sync interval")
                            .font(design.fonts.callout)
                            .foregroundColor(design.colors.textPrimary)

                        Text("How often to check for calendar updates")
                            .font(design.fonts.caption)
                            .foregroundColor(design.colors.textSecondary)
                    }

                    Spacer()

                    Picker("Interval", selection: preferences.syncIntervalSecondsBinding) {
                        Text("30 seconds").tag(Self.syncTag30Sec)
                        Text("1 minute").tag(Self.syncTag1Min)
                        Text("2 minutes").tag(Self.syncTag2Min)
                        Text("5 minutes").tag(Self.syncTag5Min)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .umPickerStyle()
                    .frame(width: Self.syncPickerWidth)
                }

                HStack {
                    VStack(alignment: .leading, spacing: design.spacing.xs) {
                        Text("All-day events")
                            .font(design.fonts.callout)
                            .foregroundColor(design.colors.textPrimary)

                        Text("Include all-day events in sync")
                            .font(design.fonts.caption)
                            .foregroundColor(design.colors.textSecondary)
                    }

                    Spacer()

                    Toggle(isOn: preferences.includeAllDayEventsBinding) {}
                        .toggleStyle(UMToggleStyle())
                        .labelsHidden()
                        .accessibilityLabel("Include all-day events")
                }
            }
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        UMSection("Startup", icon: "power") {
            HStack {
                VStack(alignment: .leading, spacing: design.spacing.xs) {
                    Text("Launch at login")
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Start Unmissable automatically when you log in")
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textSecondary)
                }

                Spacer()

                Toggle(isOn: preferences.launchAtLoginBinding) {}
                    .toggleStyle(UMToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel("Launch at login")
            }
        }
    }
}

// MARK: - Shortcuts Preferences

struct ShortcutsPreferencesView: View {
    @Environment(PreferencesManager.self)
    var preferences
    @Environment(\.design)
    private var design

    private static let shortcutBorderWidth: CGFloat = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("Keyboard Shortcuts")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Global shortcuts work even when other apps are focused")
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textSecondary)
                }

                UMSection("Global Shortcuts", icon: "keyboard") {
                    VStack(spacing: design.spacing.lg) {
                        shortcutRow(
                            title: "Dismiss overlay",
                            subtitle: "Close the current meeting alert",
                            shortcut: ShortcutsManager.dismissShortcutDisplay,
                        )

                        shortcutRow(
                            title: "Join meeting",
                            subtitle: "Quickly join the current meeting",
                            shortcut: ShortcutsManager.joinShortcutDisplay,
                        )
                    }
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
        shortcut: String,
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: design.spacing.xs) {
                Text(title)
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)

                Text(subtitle)
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textSecondary)
            }

            Spacer()

            Text(shortcut)
                .font(design.fonts.mono)
                .foregroundColor(design.colors.textPrimary)
                .padding(.horizontal, design.spacing.md)
                .padding(.vertical, design.spacing.sm)
                .background(design.colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: design.corners.md))
                .overlay(
                    RoundedRectangle(cornerRadius: design.corners.md)
                        .stroke(design.colors.borderDefault, lineWidth: Self.shortcutBorderWidth),
                )
        }
    }
}
