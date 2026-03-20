import SwiftUI

struct CalendarPreferencesView: View {
    @EnvironmentObject
    var appState: AppState
    @Environment(\.customDesign)
    private var design
    @State
    private var isConnecting = false

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
                    connectedSection
                } else {
                    disconnectedSection
                }

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }

    // MARK: - Connected State

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: design.spacing.xl) {
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
                                appState.disconnectFromCalendar()
                            }
                        }
                    }
                }
                .padding(design.spacing.lg)
            }

            calendarSelectionSection
        }
    }

    private var calendarSelectionSection: some View {
        Group {
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
                                        appState.updateCalendarSelection(
                                            calendar.id, isSelected: isSelected
                                        )
                                    }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(design.spacing.lg)
                }
            }
        }
    }

    // MARK: - Disconnected State

    private var disconnectedSection: some View {
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
}

// MARK: - Calendar Selection Row

struct CalendarSelectionRow: View {
    let calendar: CalendarInfo
    let onToggle: (Bool) -> Void
    @Environment(\.customDesign)
    private var design

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
