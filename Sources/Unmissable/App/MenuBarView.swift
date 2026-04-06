import SwiftUI

struct MenuBarView: View {
    // MARK: - Layout Constants

    private static let menuBarWidth: CGFloat = 340
    private static let statusIndicatorSize: CGFloat = 8
    private static let separatorHeight: CGFloat = 0.5
    private static let syncProgressScale: CGFloat = 0.7
    private static let maxVisibleEventsPerGroup = 3
    private static let messageLineLimit = 3
    private static let setupGuideLineLimit = 2

    @Environment(AppState.self)
    var appState
    @Environment(CalendarService.self)
    var calendarService
    @Environment(\.design)
    private var design
    @Environment(\.dismiss)
    private var dismiss

    private var includeAllDay: Bool {
        appState.preferences.includeAllDayEvents
    }

    private var groupedEvents: [EventGroup] {
        let events =
            appState.preferences.showTodayOnlyInMenuBar
                ? EventGrouping.todayEvents(from: calendarService.events, includeAllDay: includeAllDay)
                : EventGrouping.upcomingEvents(from: calendarService.events, includeAllDay: includeAllDay)

        return EventGrouping.groupByDate(
            events,
            startedEvents: calendarService.startedEvents,
            includeAllDay: includeAllDay,
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            contentSection
            footerSection
        }
        .background {
            ZStack {
                VisualEffectBackground(material: .popover)
                design.colors.glass.opacity(UMGlassModifier.glassOverlayOpacity)
            }
        }
        .frame(width: Self.menuBarWidth)
        .accessibilityIdentifier("menu-bar-view")
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: design.spacing.sm) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(design.colors.accent)
                        .font(design.fonts.body)
                        .fontWeight(.semibold)

                    Text("Unmissable")
                        .font(design.fonts.headline)
                        .tracking(DesignTracking.header)
                        .foregroundColor(design.colors.textPrimary)
                }

                Spacer()

                UMStatusIndicator(connectionStatus, size: Self.statusIndicatorSize)
            }
            .padding(.horizontal, design.spacing.lg)
            .padding(.vertical, design.spacing.md)

            Rectangle()
                .fill(design.colors.borderSubtle)
                .frame(height: Self.separatorHeight)
        }
    }

    private var contentSection: some View {
        VStack(spacing: design.spacing.lg) {
            if let dbError = appState.databaseError {
                databaseErrorCard(dbError)
            }

            if !calendarService.isConnected {
                disconnectedContent
            } else {
                connectedContent
            }
        }
        .padding(.vertical, design.spacing.lg)
    }

    @State
    private var isRetryingDatabase = false

    private func databaseErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: design.spacing.sm) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(design.colors.error)
                    .font(design.fonts.body)
                    .fontWeight(.medium)

                Text("Database Error")
                    .font(design.fonts.callout)
                    .fontWeight(.medium)
                    .foregroundColor(design.colors.error)
            }

            Text(message)
                .font(design.fonts.caption)
                .foregroundColor(design.colors.textSecondary)
                .lineLimit(Self.messageLineLimit)
                .multilineTextAlignment(.leading)

            HStack(spacing: design.spacing.sm) {
                Button {
                    Task {
                        isRetryingDatabase = true
                        await appState.retryDatabaseInitialization()
                        isRetryingDatabase = false
                    }
                } label: {
                    Label(
                        isRetryingDatabase ? "Retrying..." : "Retry",
                        systemImage: "arrow.clockwise",
                    )
                }
                .buttonStyle(UMButtonStyle(.secondary, size: .sm))
                .disabled(isRetryingDatabase)
                .accessibilityIdentifier("retry-database-button")
                .accessibilityLabel("Retry database initialization")

                if !isRetryingDatabase {
                    Text("or restart the app")
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textTertiary)
                }
            }
        }
        .padding(design.spacing.md)
        .umCard(.flat)
        .padding(.horizontal, design.spacing.lg)
    }

    private var footerSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(design.colors.borderSubtle)
                .frame(height: Self.separatorHeight)

            HStack {
                Button("Preferences") {
                    dismiss()
                    appState.showPreferences()
                }
                .buttonStyle(UMButtonStyle(.ghost, size: .sm))
                .accessibilityIdentifier("preferences-button")

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(UMButtonStyle(.ghost, size: .sm))
                .accessibilityIdentifier("quit-button")
            }
            .padding(.horizontal, design.spacing.md)
            .padding(.vertical, design.spacing.sm)
        }
    }

    // MARK: - Content States

    private var disconnectedContent: some View {
        VStack(spacing: design.spacing.lg) {
            if let authError = calendarService.authError {
                VStack(alignment: .leading, spacing: design.spacing.sm) {
                    HStack(spacing: design.spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(design.colors.error)
                            .font(design.fonts.body)
                            .fontWeight(.medium)

                        Text("Connection Error")
                            .font(design.fonts.callout)
                            .fontWeight(.medium)
                            .foregroundColor(design.colors.error)
                    }

                    Text(authError)
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textSecondary)
                        .lineLimit(Self.messageLineLimit)
                        .multilineTextAlignment(.leading)

                    if authError.contains("configuration") {
                        Text("See OAUTH_SETUP_GUIDE.md for setup instructions")
                            .font(design.fonts.caption)
                            .foregroundColor(design.colors.accent)
                            .lineLimit(Self.setupGuideLineLimit)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(design.spacing.md)
                .umCard(.flat)
            }

            VStack(spacing: design.spacing.md) {
                Button {
                    Task { await appState.connectToCalendar(provider: .apple) }
                } label: {
                    Label("Connect Apple Calendar", systemImage: "apple.logo")
                }
                .buttonStyle(UMButtonStyle(.primary))
                .accessibilityIdentifier("connect-apple-calendar-button")

                Button {
                    Task { await appState.connectToCalendar(provider: .google) }
                } label: {
                    Label("Connect Google Calendar", systemImage: "calendar")
                }
                .buttonStyle(UMButtonStyle(.secondary))
                .accessibilityIdentifier("connect-google-calendar-button")
            }
        }
        .padding(.horizontal, design.spacing.lg)
    }

    private var connectedContent: some View {
        VStack(spacing: design.spacing.lg) {
            syncStatusBar
            eventsListSection
        }
    }

    private var syncStatusBar: some View {
        HStack {
            HStack(spacing: design.spacing.sm) {
                syncStatusIcon
                Text(calendarService.syncStatus.description)
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textSecondary)
                    .accessibilityIdentifier("sync-status-text")
            }

            Spacer()

            if case .syncing = calendarService.syncStatus {
                ProgressView()
                    .scaleEffect(Self.syncProgressScale)
                    .tint(design.colors.accent)
            } else {
                Button("Sync") {
                    Task { await appState.syncNow() }
                }
                .buttonStyle(UMButtonStyle(.ghost, size: .sm))
                .accessibilityIdentifier("sync-button")
            }
        }
        .padding(.horizontal, design.spacing.lg)
    }

    private var eventsListSection: some View {
        VStack(spacing: design.spacing.md) {
            HStack {
                Text("Show today only")
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textSecondary)

                Spacer()

                Toggle(isOn: appState.preferences.showTodayOnlyInMenuBarBinding) {}
                    .toggleStyle(UMToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel("Show today only")
            }
            .padding(.horizontal, design.spacing.lg)

            if groupedEvents.isEmpty {
                HStack(spacing: design.spacing.sm) {
                    Image(systemName: "calendar")
                        .foregroundColor(design.colors.textTertiary)
                        .font(design.fonts.body)

                    Text("No upcoming meetings")
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textTertiary)
                        .accessibilityIdentifier("no-events-text")
                }
                .padding(design.spacing.lg)
                .umCard(.flat)
                .padding(.horizontal, design.spacing.lg)
            } else {
                ForEach(groupedEvents) { group in
                    eventGroupView(group)
                }
            }
        }
    }

    private func eventGroupView(_ group: EventGroup) -> some View {
        VStack(spacing: design.spacing.sm) {
            HStack {
                Text(group.title.uppercased())
                    .font(design.fonts.sectionLabel)
                    .tracking(DesignTracking.sectionLabel)
                    .foregroundColor(design.colors.accent)

                Spacer()
            }
            .padding(.horizontal, design.spacing.lg)

            ForEach(group.events.prefix(Self.maxVisibleEventsPerGroup)) { event in
                EventRow(
                    event: event,
                    linkParser: appState.linkParser,
                    onEventTap: {
                        appState.showMeetingDetails(for: event)
                    },
                )
                .padding(.horizontal, design.spacing.lg)
            }

            if group.events.count > Self.maxVisibleEventsPerGroup {
                Text("and \(group.events.count - Self.maxVisibleEventsPerGroup) more")
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textTertiary)
                    .padding(.horizontal, design.spacing.lg)
                    .accessibilityIdentifier("more-events-indicator")
            }
        }
    }

    private var syncStatusIcon: some View {
        Group {
            switch calendarService.syncStatus {
            case .idle:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(design.colors.success)

            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(design.colors.accent)

            case .offline:
                Image(systemName: "wifi.slash")
                    .foregroundColor(design.colors.warning)

            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(design.colors.error)
            }
        }
        .font(design.fonts.callout)
        .fontWeight(.medium)
    }

    private var connectionStatus: UMStatusIndicator.Status {
        if !calendarService.isConnected {
            return .disconnected
        }

        switch calendarService.syncStatus {
        case .idle:
            return .connected
        case .syncing:
            return .connecting
        case .offline:
            return .disconnected
        case .error:
            return .error
        }
    }
}
