import SwiftUI

struct CalendarPreferencesView: View {
    @Environment(AppState.self)
    var appState
    @Environment(CalendarService.self)
    var calendarService
    @Environment(\.design)
    private var design
    @State
    private var connectingProvider: CalendarProviderType?

    private static let providerIconWidth: CGFloat = 32
    private static let statusIndicatorSize: CGFloat = 10
    private static let progressScaleAmount: CGFloat = 0.8
    private static let errorLineLimit = 2
    private static let colorDotSize: CGFloat = 10
    private static let colorDotTopPadding: CGFloat = 4
    private static let primaryBadgeBackgroundOpacity: Double = 0.1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    Text("Calendar Connection")
                        .font(design.fonts.title2)
                        .foregroundColor(design.colors.textPrimary)

                    Text("Connect your calendars and choose which ones to monitor")
                        .font(design.fonts.caption)
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
                            .font(design.fonts.footnote)

                        Text(updateError)
                            .font(design.fonts.caption)
                            .foregroundColor(design.colors.warning)
                            .lineLimit(Self.errorLineLimit)
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

        return HStack(spacing: design.spacing.md) {
            Image(systemName: providerType.iconName)
                .foregroundColor(isConnected ? design.colors.accent : design.colors.textSecondary)
                .font(design.fonts.title2)
                .fontWeight(.medium)
                .frame(width: Self.providerIconWidth)

            VStack(alignment: .leading, spacing: design.spacing.xs) {
                HStack(spacing: design.spacing.sm) {
                    Text(providerType.displayName)
                        .font(design.fonts.headline)
                        .foregroundColor(design.colors.textPrimary)

                    if isConnected {
                        UMStatusIndicator(.connected, size: Self.statusIndicatorSize)
                    }
                }

                if isConnected {
                    providerStatusText(for: providerType)
                } else {
                    Text("Not connected")
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textSecondary)
                }
            }

            Spacer()

            if isConnected {
                Button {
                    Task {
                        await appState.disconnectFromCalendar(provider: providerType)
                    }
                } label: {
                    Text("Disconnect")
                }
                .buttonStyle(UMButtonStyle(.danger))
            } else if isConnecting {
                ProgressView()
                    .scaleEffect(Self.progressScaleAmount)
                    .tint(design.colors.accent)
            } else {
                Button {
                    connectingProvider = providerType
                    Task {
                        await appState.connectToCalendar(provider: providerType)
                        connectingProvider = nil
                    }
                } label: {
                    Text("Connect")
                }
                .buttonStyle(UMButtonStyle(.primary))
            }
        }
        .padding(design.spacing.lg)
        .umCard(isConnected ? .elevated : .glass)
    }

    @ViewBuilder
    private func providerStatusText(for providerType: CalendarProviderType) -> some View {
        switch providerType {
        case .google:
            if let email = calendarService.userEmail {
                Text(email)
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textSecondary)
            } else {
                Text("Connected")
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textSecondary)
            }

        case .apple:
            let appleCalendarCount = calendarService.calendars.count(where: { $0.sourceProvider == .apple })
            if appleCalendarCount > 0 {
                Text("\(appleCalendarCount) calendar\(appleCalendarCount == 1 ? "" : "s") available")
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textSecondary)
            } else {
                Text("Connected")
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textSecondary)
            }
        }
    }

    // MARK: - Calendar Selection

    private var calendarSelectionSection: some View {
        Group {
            if calendarService.calendars.isEmpty {
                HStack(spacing: design.spacing.sm) {
                    ProgressView()
                        .scaleEffect(Self.progressScaleAmount)
                        .tint(design.colors.accent)
                    Text("Loading calendars...")
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textSecondary)
                }
                .padding(design.spacing.lg)
                .umCard(.glass)
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
                    UMSection("\(providerType.displayName) Calendars", icon: providerType.iconName) {
                        VStack(alignment: .leading, spacing: design.spacing.sm) {
                            ForEach(providerCalendars) { calendar in
                                CalendarSelectionRow(
                                    calendar: calendar,
                                    onToggle: { isSelected in
                                        appState.updateCalendarSelection(
                                            calendar.id, isSelected: isSelected,
                                        )
                                    },
                                    onAlertModeChange: { mode in
                                        appState.updateCalendarAlertMode(
                                            calendar.id, alertMode: mode,
                                        )
                                    },
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    let onAlertModeChange: (AlertMode) -> Void
    @Environment(\.design)
    private var design

    private static let colorDotSize: CGFloat = 10
    private static let colorDotTopPadding: CGFloat = 4
    private static let descriptionLineLimit = 2

    var body: some View {
        HStack(alignment: .top, spacing: design.spacing.md) {
            Toggle(
                isOn: Binding(
                    get: { calendar.isSelected },
                    set: { onToggle($0) },
                ),
            ) {}
                .toggleStyle(UMToggleStyle())
                .labelsHidden()
                .accessibilityLabel("Toggle \(calendar.name)")

            VStack(alignment: .leading, spacing: design.spacing.xs) {
                HStack(alignment: .top, spacing: design.spacing.sm) {
                    if let colorHex = calendar.colorHex {
                        Circle()
                            .fill(Color(hex: colorHex) ?? design.colors.accent)
                            .frame(width: Self.colorDotSize, height: Self.colorDotSize)
                            .padding(.top, Self.colorDotTopPadding)
                    }

                    Text(calendar.name)
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)

                    if calendar.isPrimary {
                        UMBadge("PRIMARY", variant: .accent)
                    }

                    Spacer()
                }

                if let description = calendar.description, !description.isEmpty {
                    Text(description)
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textSecondary)
                        .lineLimit(Self.descriptionLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if calendar.isSelected {
                    alertModePicker
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(design.spacing.md)
        .background(design.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: design.corners.md))
    }

    private var alertModePicker: some View {
        Picker("Alert", selection: Binding(
            get: { calendar.alertMode },
            set: { onAlertModeChange($0) },
        )) {
            ForEach(AlertMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .umPickerStyle()
        .accessibilityLabel("Alert mode for \(calendar.name)")
    }
}

// MARK: - Color Extension for Hex

private extension Color {
    private static let hexStringLength = 6
    private static let hexRadix = 16
    private static let redShift: UInt64 = 16
    private static let greenShift: UInt64 = 8
    private static let channelMask: UInt64 = 0xFF
    private static let channelMax: Double = 255.0

    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized

        guard hexSanitized.count == Self.hexStringLength,
              let rgb = UInt64(hexSanitized, radix: Self.hexRadix)
        else {
            return nil
        }

        self.init(
            red: Double((rgb >> Self.redShift) & Self.channelMask) / Self.channelMax,
            green: Double((rgb >> Self.greenShift) & Self.channelMask) / Self.channelMax,
            blue: Double(rgb & Self.channelMask) / Self.channelMax,
        )
    }
}
