import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.customDesign) private var design
    @State private var selectedTab = 0

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
            .environmentObject(appState.preferencesManagerPublic)
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
    @EnvironmentObject var preferences: PreferencesManager
    @Environment(\.customDesign) private var design

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

                // Alert timing section
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
                            // Default alert time
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

                            // Length-based timing
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

                            if preferences.useLengthBasedTiming {
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
                        }
                    }
                    .padding(design.spacing.lg)
                }

                // Sync settings section
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

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }
}

// MARK: - Calendar Preferences

struct CalendarPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var preferences: PreferencesManager
    @Environment(\.customDesign) private var design
    @State private var isConnecting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("Calendar Connection")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Connect your calendar and choose which calendars to monitor")
                        .font(design.fonts.caption1)
                        .foregroundColor(design.colors.textSecondary)
                }

                if appState.isConnectedToCalendar {
                    // Connected state
                    CustomCard(style: .elevated) {
                        VStack(spacing: design.spacing.lg) {
                            HStack(spacing: design.spacing.md) {
                                CustomStatusIndicator(status: .connected, size: 16)

                                VStack(alignment: .leading, spacing: design.spacing.xs) {
                                    Text("Connected to Google Calendar")
                                        .font(design.fonts.headline)
                                        .foregroundColor(design.colors.textPrimary)

                                    if let email = appState.userEmail {
                                        Text(email)
                                            .font(design.fonts.callout)
                                            .foregroundColor(design.colors.textSecondary)
                                    }
                                }

                                Spacer()

                                CustomButton("Disconnect", style: .destructive) {
                                    Task {
                                        await appState.disconnectFromCalendar()
                                    }
                                }
                            }
                        }
                        .padding(design.spacing.lg)
                    }

                    // Calendar Selection
                    if appState.calendars.isEmpty {
                        CustomCard(style: .standard) {
                            HStack(spacing: design.spacing.sm) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(design.colors.accent)
                                Text("Loading calendars...")
                                    .font(design.fonts.callout)
                                    .foregroundColor(design.colors.textSecondary)
                            }
                            .padding(design.spacing.lg)
                        }
                    } else {
                        CustomCard(style: .standard) {
                            VStack(alignment: .leading, spacing: design.spacing.lg) {
                                Text("Calendar Selection")
                                    .font(design.fonts.headline)
                                    .foregroundColor(design.colors.textPrimary)

                                VStack(alignment: .leading, spacing: design.spacing.sm) {
                                    ForEach(appState.calendars) { calendar in
                                        CalendarSelectionRow(
                                            calendar: calendar,
                                            onToggle: { isSelected in
                                                appState.updateCalendarSelection(calendar.id, isSelected: isSelected)
                                            }
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(design.spacing.lg)
                        }
                    }
                } else {
                    // Disconnected state
                    CustomCard(style: .elevated) {
                        VStack(spacing: design.spacing.lg) {
                            HStack(spacing: design.spacing.md) {
                                CustomStatusIndicator(status: .disconnected, size: 16)

                                VStack(alignment: .leading, spacing: design.spacing.xs) {
                                    Text("Not connected to Google Calendar")
                                        .font(design.fonts.headline)
                                        .foregroundColor(design.colors.textPrimary)

                                    Text(
                                        "Connect your Google Calendar to receive meeting alerts and never miss important meetings."
                                    )
                                    .font(design.fonts.callout)
                                    .foregroundColor(design.colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            VStack(spacing: design.spacing.md) {
                                CustomButton("Connect Google Calendar", icon: "link", style: .primary) {
                                    isConnecting = true
                                    Task {
                                        await appState.connectToCalendar()
                                        isConnecting = false
                                    }
                                }
                                .disabled(isConnecting)

                                if isConnecting {
                                    HStack(spacing: design.spacing.sm) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(design.colors.accent)
                                        Text("Connecting...")
                                            .font(design.fonts.callout)
                                            .foregroundColor(design.colors.textSecondary)
                                    }
                                }

                                if let error = appState.authError {
                                    Text("Error: \(error)")
                                        .font(design.fonts.caption1)
                                        .foregroundColor(design.colors.error)
                                        .padding(design.spacing.sm)
                                        .background(design.colors.error.opacity(0.1))
                                        .cornerRadius(design.corners.medium)
                                }
                            }
                        }
                        .padding(design.spacing.lg)
                    }
                }

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }
}

struct CalendarSelectionRow: View {
    let calendar: CalendarInfo
    let onToggle: (Bool) -> Void
    @Environment(\.customDesign) private var design

    var body: some View {
        HStack(alignment: .top, spacing: design.spacing.md) {
            CustomToggle(
                isOn: Binding(
                    get: { calendar.isSelected },
                    set: { onToggle($0) }
                )
            )

            VStack(alignment: .leading, spacing: design.spacing.xs) {
                HStack(alignment: .top, spacing: design.spacing.sm) {
                    Text(calendar.name)
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)

                    if calendar.isPrimary {
                        Text("PRIMARY")
                            .font(design.fonts.caption2)
                            .foregroundColor(design.colors.accent)
                            .padding(.horizontal, design.spacing.sm)
                            .padding(.vertical, design.spacing.xs)
                            .background(design.colors.accent.opacity(0.1))
                            .cornerRadius(design.corners.small)
                    }

                    Spacer()
                }

                if let description = calendar.description, !description.isEmpty {
                    Text(description)
                        .font(design.fonts.caption1)
                        .foregroundColor(design.colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(design.spacing.md)
        .background(design.colors.backgroundSecondary)
        .cornerRadius(design.corners.medium)
    }
}

// MARK: - Appearance Preferences

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
                            HStack {
                                VStack(alignment: .leading, spacing: design.spacing.xs) {
                                    Text("Dismiss overlay")
                                        .font(design.fonts.callout)
                                        .foregroundColor(design.colors.textPrimary)

                                    Text("Close the current meeting alert")
                                        .font(design.fonts.caption1)
                                        .foregroundColor(design.colors.textSecondary)
                                }

                                Spacer()

                                Text("⌘⎋")
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

                            HStack {
                                VStack(alignment: .leading, spacing: design.spacing.xs) {
                                    Text("Join meeting")
                                        .font(design.fonts.callout)
                                        .foregroundColor(design.colors.textPrimary)

                                    Text("Quickly join the current meeting")
                                        .font(design.fonts.caption1)
                                        .foregroundColor(design.colors.textSecondary)
                                }

                                Spacer()

                                Text("⌘⏎")
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
                    .padding(design.spacing.lg)
                }

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }
}

#Preview("Preferences - Light") {
    PreferencesView()
        .environmentObject(AppState())
        .onAppear {
            ThemeManager.shared.setTheme(.light)
        }
}

#Preview("Preferences - Dark") {
    PreferencesView()
        .environmentObject(AppState())
        .onAppear {
            ThemeManager.shared.setTheme(.dark)
        }
}
