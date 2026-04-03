import SwiftUI

/// Event grouping structure for date-based organization
struct EventGroup: Identifiable {
    let title: String
    let events: [Event]

    var id: String {
        title
    }
}

struct MenuBarView: View {
    @EnvironmentObject
    var appState: AppState
    @EnvironmentObject
    var calendarService: CalendarService
    @Environment(\.customDesign)
    private var design

    private var groupedEvents: [EventGroup] {
        let events =
            appState.preferences.showTodayOnlyInMenuBar
                ? filteredTodayEvents
                : filteredEventsForDisplay

        return groupEventsByDate(events, includingStarted: true)
    }

    /// Applies the all-day event preference filter.
    private func applyAllDayFilter(_ events: [Event]) -> [Event] {
        if appState.preferences.includeAllDayEvents {
            return events
        }
        return events.filter { !$0.isAllDay }
    }

    private var filteredTodayEvents: [Event] {
        let calendar = Calendar.current
        let today = Date()

        let dateFiltered = calendarService.events.filter { event in
            calendar.isDate(event.startDate, inSameDayAs: today)
        }
        return applyAllDayFilter(dateFiltered)
    }

    private var filteredEventsForDisplay: [Event] {
        let calendar = Calendar.current
        let today = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            let dateFiltered = calendarService.events.filter { event in
                calendar.isDate(event.startDate, inSameDayAs: today)
            }
            return applyAllDayFilter(dateFiltered)
        }
        let monday = getNextMondayIfNeeded(from: tomorrow, calendar: calendar)

        let dateFiltered = calendarService.events.filter { event in
            calendar.isDate(event.startDate, inSameDayAs: today)
                || calendar.isDate(event.startDate, inSameDayAs: tomorrow)
                || (monday.map { calendar.isDate(event.startDate, inSameDayAs: $0) } ?? false)
        }
        return applyAllDayFilter(dateFiltered)
    }

    private func getNextMondayIfNeeded(from tomorrow: Date, calendar: Calendar) -> Date? {
        // If tomorrow is Saturday, also include Monday
        // Using isDateInWeekend for clarity, then checking it's the first weekend day (Saturday)
        if calendar.isDateInWeekend(tomorrow),
           let nextDay = calendar.date(byAdding: .day, value: 1, to: tomorrow),
           calendar.isDateInWeekend(nextDay)
        {
            // Tomorrow is Saturday (both tomorrow and the day after are weekend days)
            return calendar.date(byAdding: .day, value: 2, to: tomorrow)
        }
        return nil
    }

    private func groupEventsByDate(_ events: [Event], includingStarted: Bool = false) -> [EventGroup] {
        let calendar = Calendar.current
        let today = Date()

        var groups: [EventGroup] = []

        // Add started meetings group if including started events
        if includingStarted {
            let startedMeetings = applyAllDayFilter(calendarService.startedEvents)
            if !startedMeetings.isEmpty {
                groups.append(EventGroup(title: "Started", events: startedMeetings))
            }
        }

        // Group events by date
        let todayEvents = events.filter { calendar.isDate($0.startDate, inSameDayAs: today) }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            // Fallback: show today's events even if tomorrow can't be computed
            if !todayEvents.isEmpty {
                groups.append(EventGroup(title: "Today", events: todayEvents))
            }
            return groups
        }

        let tomorrowEvents = events.filter { calendar.isDate($0.startDate, inSameDayAs: tomorrow) }

        // Get next-workday events if tomorrow starts a weekend
        var nextWorkdayEvents: [Event] = []
        var nextWorkdayTitle = ""
        if let nextWorkday = getNextMondayIfNeeded(from: tomorrow, calendar: calendar) {
            nextWorkdayEvents = events.filter { calendar.isDate($0.startDate, inSameDayAs: nextWorkday) }
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Full day name, locale-aware
            nextWorkdayTitle = formatter.string(from: nextWorkday)
        }

        // Add non-empty groups
        if !todayEvents.isEmpty {
            groups.append(EventGroup(title: "Today", events: todayEvents))
        }

        if !tomorrowEvents.isEmpty {
            groups.append(EventGroup(title: "Tomorrow", events: tomorrowEvents))
        }

        if !nextWorkdayEvents.isEmpty {
            groups.append(EventGroup(title: nextWorkdayTitle, events: nextWorkdayEvents))
        }

        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            contentSection
            footerSection
        }
        .background(.ultraThinMaterial)
        .background(design.colors.background.opacity(0.85))
        .frame(width: 340)
        .accessibilityIdentifier("menu-bar-view")
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: design.spacing.sm) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(design.colors.accent)
                        .font(.system(size: 16, weight: .semibold))

                    Text("Unmissable")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(design.colors.textPrimary)
                }

                Spacer()

                CustomStatusIndicator(status: connectionStatus, size: 8)
            }
            .padding(.horizontal, design.spacing.lg)
            .padding(.vertical, design.spacing.md)

            Rectangle()
                .fill(design.colors.divider)
                .frame(height: 0.5)
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
        CustomCard(style: .flat) {
            VStack(alignment: .leading, spacing: design.spacing.sm) {
                HStack(spacing: design.spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(design.colors.error)
                        .font(.system(size: 16, weight: .medium))

                    Text("Database Error")
                        .font(design.fonts.subheadline)
                        .foregroundColor(design.colors.error)
                }

                Text(message)
                    .font(design.fonts.caption1)
                    .foregroundColor(design.colors.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: design.spacing.sm) {
                    CustomButton(
                        isRetryingDatabase ? "Retrying…" : "Retry",
                        icon: "arrow.clockwise",
                        style: .secondary
                    ) {
                        Task {
                            isRetryingDatabase = true
                            await appState.retryDatabaseInitialization()
                            isRetryingDatabase = false
                        }
                    }
                    .disabled(isRetryingDatabase)
                    .accessibilityIdentifier("retry-database-button")
                    .accessibilityLabel("Retry database initialization")

                    if !isRetryingDatabase {
                        Text("or restart the app")
                            .font(design.fonts.caption2)
                            .foregroundColor(design.colors.textTertiary)
                    }
                }
            }
            .padding(design.spacing.md)
        }
        .padding(.horizontal, design.spacing.lg)
    }

    private var footerSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(design.colors.divider)
                .frame(height: 0.5)

            HStack {
                CustomButton("Preferences", style: .minimal) {
                    appState.showPreferences()
                }
                .accessibilityIdentifier("preferences-button")

                Spacer()

                CustomButton("Check for Updates", style: .minimal) {
                    appState.checkForUpdates()
                }
                .disabled(!appState.canCheckForUpdates)
                .accessibilityIdentifier("check-updates-button")

                Spacer()

                CustomButton("Quit", style: .minimal) {
                    NSApplication.shared.terminate(nil)
                }
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
                CustomCard(style: .flat) {
                    VStack(alignment: .leading, spacing: design.spacing.sm) {
                        HStack(spacing: design.spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(design.colors.error)
                                .font(.system(size: 16, weight: .medium))

                            Text("Connection Error")
                                .font(design.fonts.subheadline)
                                .foregroundColor(design.colors.error)
                        }

                        Text(authError)
                            .font(design.fonts.caption1)
                            .foregroundColor(design.colors.textSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        if authError.contains("configuration") {
                            Text("See OAUTH_SETUP_GUIDE.md for setup instructions")
                                .font(design.fonts.caption2)
                                .foregroundColor(design.colors.interactive)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(design.spacing.md)
                }
            }

            VStack(spacing: design.spacing.md) {
                CustomButton("Connect Apple Calendar", icon: "apple.logo", style: .primary) {
                    Task {
                        await appState.connectToCalendar(provider: .apple)
                    }
                }
                .accessibilityIdentifier("connect-apple-calendar-button")

                CustomButton("Connect Google Calendar", icon: "calendar", style: .secondary) {
                    Task {
                        await appState.connectToCalendar(provider: .google)
                    }
                }
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
                    .font(design.fonts.caption1)
                    .foregroundColor(design.colors.textSecondary)
                    .accessibilityIdentifier("sync-status-text")
            }

            Spacer()

            if case .syncing = calendarService.syncStatus {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(design.colors.accent)
            } else {
                CustomButton("Sync", style: .minimal) {
                    Task {
                        await appState.syncNow()
                    }
                }
                .accessibilityIdentifier("sync-button")
            }
        }
        .padding(.horizontal, design.spacing.lg)
    }

    private var eventsListSection: some View {
        Group {
            if groupedEvents.isEmpty {
                CustomCard(style: .flat) {
                    HStack(spacing: design.spacing.sm) {
                        Image(systemName: "calendar")
                            .foregroundColor(design.colors.textTertiary)
                            .font(.system(size: 16))

                        Text("No upcoming meetings")
                            .font(design.fonts.callout)
                            .foregroundColor(design.colors.textTertiary)
                            .accessibilityIdentifier("no-events-text")
                    }
                    .padding(design.spacing.lg)
                }
                .padding(.horizontal, design.spacing.lg)
            } else {
                VStack(spacing: design.spacing.md) {
                    HStack {
                        Text("Show today only")
                            .font(design.fonts.caption1)
                            .foregroundColor(design.colors.textSecondary)

                        Spacer()

                        CustomToggle(
                            isOn: appState.preferences.showTodayOnlyInMenuBarBinding
                        )
                    }
                    .padding(.horizontal, design.spacing.lg)

                    ForEach(groupedEvents) { group in
                        eventGroupView(group)
                    }
                }
            }
        }
    }

    private func eventGroupView(_ group: EventGroup) -> some View {
        VStack(spacing: design.spacing.sm) {
            HStack {
                Text(group.title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(design.colors.accentSecondary)

                Spacer()
            }
            .padding(.horizontal, design.spacing.lg)

            ForEach(group.events.prefix(3)) { event in
                CustomEventRow(
                    event: event,
                    linkParser: appState.linkParser,
                    onEventTap: {
                        appState.showMeetingDetails(for: event)
                    }
                )
                .padding(.horizontal, design.spacing.lg)
            }

            if group.events.count > 3 {
                Text("and \(group.events.count - 3) more")
                    .font(design.fonts.caption1)
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
        .font(.system(size: 14, weight: .medium))
    }

    private var connectionStatus: CustomStatusIndicator.Status {
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

// MARK: - Custom Event Row

struct CustomEventRow: View {
    let event: Event
    let linkParser: LinkParser
    let onEventTap: (() -> Void)?
    @Environment(\.customDesign)
    private var design
    @State
    private var isHovered = false

    init(event: Event, linkParser: LinkParser, onEventTap: (() -> Void)? = nil) {
        self.event = event
        self.linkParser = linkParser
        self.onEventTap = onEventTap
    }

    var body: some View {
        CustomCard(style: .standard) {
            HStack(spacing: design.spacing.md) {
                VStack(alignment: .leading, spacing: design.spacing.xs) {
                    Text(event.title)
                        .font(design.fonts.callout)
                        .fontWeight(.medium)
                        .foregroundColor(design.colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: design.spacing.xs) {
                        Image(systemName: "clock")
                            .foregroundColor(design.colors.accent)
                            .font(.system(size: 11, weight: .medium))

                        Text(event.startDate, style: .time)
                            .font(design.fonts.monoTimestamp)
                            .foregroundColor(design.colors.textSecondary)
                    }
                }

                Spacer()

                HStack(spacing: design.spacing.md) {
                    if linkParser.isOnlineMeeting(event) {
                        Image(systemName: event.provider?.iconName ?? "link")
                            .foregroundColor(design.colors.accent)
                            .font(.system(size: 14, weight: .medium))
                    }

                    if linkParser.shouldShowJoinButton(for: event),
                       let primaryLink = linkParser.primaryLink(for: event)
                    {
                        CustomButton("Join", icon: "video.fill", style: .secondary) {
                            NSWorkspace.shared.open(primaryLink)
                        }
                    }
                }
            }
            .padding(design.spacing.md)
            .background(
                isHovered ? design.colors.accent.opacity(0.05) : Color.clear
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .onTapGesture {
                onEventTap?()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Meeting: \(event.title) at \(event.startDate, style: .time)")
            .accessibilityIdentifier("event-row-\(event.id)")
            .accessibilityHint("Tap to view meeting details")
        }
    }
}

// Preview removed: MenuBarView requires AppState which creates real
// OverlayManager and CalendarService instances.
