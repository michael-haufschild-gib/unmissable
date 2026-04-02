import SwiftUI

struct CalendarPreferencesView: View {
    @EnvironmentObject
    var appState: AppState
    @EnvironmentObject
    var calendarService: CalendarService
    @Environment(\.customDesign)
    private var design
    @State
    private var connectingProvider: CalendarProviderType?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("Calendar Connection")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Connect your calendars and choose which ones to monitor")
                        .font(design.fonts.caption1)
                        .foregroundColor(design.colors.textSecondary)
                }

                providerConnectionSection

                if calendarService.isConnected {
                    calendarSelectionSection
                }

                if let updateError = calendarService.calendarUpdateError {
                    HStack(spacing: design.spacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(design.colors.warning)
                            .font(.system(size: 12))

                        Text(updateError)
                            .font(design.fonts.caption1)
                            .foregroundColor(design.colors.warning)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, design.spacing.lg)
                }

                Spacer()
            }
            .padding(design.spacing.xl)
        }
        .background(design.colors.background)
    }

    // MARK: - Provider Connection

    private var providerConnectionSection: some View {
        VStack(alignment: .leading, spacing: design.spacing.lg) {
            ForEach(CalendarProviderType.allCases, id: \.self) { providerType in
                providerCard(for: providerType)
            }
        }
    }

    private func providerCard(for providerType: CalendarProviderType) -> some View {
        let isConnected = calendarService.connectedProviders.contains(providerType)
        let isConnecting = connectingProvider == providerType

        return CustomCard(style: isConnected ? .elevated : .standard) {
            HStack(spacing: design.spacing.md) {
                Image(systemName: providerType.iconName)
                    .foregroundColor(isConnected ? design.colors.accent : design.colors.textSecondary)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: design.spacing.xs) {
                    HStack(spacing: design.spacing.sm) {
                        Text(providerType.displayName)
                            .font(design.fonts.headline)
                            .foregroundColor(design.colors.textPrimary)

                        if isConnected {
                            CustomStatusIndicator(status: .connected, size: 10)
                        }
                    }

                    if isConnected {
                        providerStatusText(for: providerType)
                    } else {
                        Text("Not connected")
                            .font(design.fonts.caption1)
                            .foregroundColor(design.colors.textSecondary)
                    }
                }

                Spacer()

                if isConnected {
                    CustomButton("Disconnect", style: .destructive) {
                        Task {
                            await appState.disconnectFromCalendar(provider: providerType)
                        }
                    }
                } else if isConnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(design.colors.accent)
                } else {
                    CustomButton("Connect", style: .primary) {
                        connectingProvider = providerType
                        Task {
                            await appState.connectToCalendar(provider: providerType)
                            connectingProvider = nil
                        }
                    }
                }
            }
            .padding(design.spacing.lg)
        }
    }

    @ViewBuilder
    private func providerStatusText(for providerType: CalendarProviderType) -> some View {
        switch providerType {
        case .google:
            if let email = calendarService.userEmail {
                Text(email)
                    .font(design.fonts.caption1)
                    .foregroundColor(design.colors.textSecondary)
            } else {
                Text("Connected")
                    .font(design.fonts.caption1)
                    .foregroundColor(design.colors.textSecondary)
            }

        case .apple:
            let appleCalendarCount = calendarService.calendars.count(where: { $0.sourceProvider == .apple })
            if appleCalendarCount > 0 {
                Text("\(appleCalendarCount) calendar\(appleCalendarCount == 1 ? "" : "s") available")
                    .font(design.fonts.caption1)
                    .foregroundColor(design.colors.textSecondary)
            } else {
                Text("Connected")
                    .font(design.fonts.caption1)
                    .foregroundColor(design.colors.textSecondary)
            }
        }
    }

    // MARK: - Calendar Selection

    private var calendarSelectionSection: some View {
        Group {
            if calendarService.calendars.isEmpty {
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
                calendarListByProvider
            }
        }
    }

    private var calendarListByProvider: some View {
        VStack(alignment: .leading, spacing: design.spacing.lg) {
            ForEach(CalendarProviderType.allCases, id: \.self) { providerType in
                let providerCalendars = calendarService.calendars.filter { $0.sourceProvider == providerType }
                if !providerCalendars.isEmpty {
                    CustomCard(style: .standard) {
                        VStack(alignment: .leading, spacing: design.spacing.lg) {
                            HStack(spacing: design.spacing.sm) {
                                Image(systemName: providerType.iconName)
                                    .foregroundColor(design.colors.accent)
                                    .font(.system(size: 14, weight: .medium))

                                Text("\(providerType.displayName) Calendars")
                                    .font(design.fonts.headline)
                                    .foregroundColor(design.colors.textPrimary)
                            }

                            VStack(alignment: .leading, spacing: design.spacing.sm) {
                                ForEach(providerCalendars) { calendar in
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
                    if let colorHex = calendar.colorHex {
                        Circle()
                            .fill(Color(hex: colorHex) ?? design.colors.accent)
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)
                    }

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

// MARK: - Color Extension for Hex

private extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16)
        else {
            return nil
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
