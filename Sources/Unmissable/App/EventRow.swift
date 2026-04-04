import SwiftUI

/// Defines the available per-event alert override options shown in the context menu.
enum AlertOverrideOption: CaseIterable {
    case defaultTiming
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case tenMinutes
    case fifteenMinutes
    case noAlert

    // Named constants for timing values (minutes before event)
    private static let noAlertValue = 0
    private static let oneMinuteValue = 1
    private static let twoMinuteValue = 2
    private static let fiveMinuteValue = 5
    private static let tenMinuteValue = 10
    private static let fifteenMinuteValue = 15

    /// The override value to store. `nil` means "use default timing".
    var minutes: Int? {
        switch self {
        case .defaultTiming: nil
        case .oneMinute: Self.oneMinuteValue
        case .twoMinutes: Self.twoMinuteValue
        case .fiveMinutes: Self.fiveMinuteValue
        case .tenMinutes: Self.tenMinuteValue
        case .fifteenMinutes: Self.fifteenMinuteValue
        case .noAlert: Self.noAlertValue
        }
    }

    var label: String {
        switch self {
        case .defaultTiming: "Default timing"
        case .oneMinute: "1 minute before"
        case .twoMinutes: "2 minutes before"
        case .fiveMinutes: "5 minutes before"
        case .tenMinutes: "10 minutes before"
        case .fifteenMinutes: "15 minutes before"
        case .noAlert: "No alert"
        }
    }

    var iconName: String {
        switch self {
        case .defaultTiming: "arrow.uturn.backward"
        case .noAlert: "bell.slash"
        default: "bell"
        }
    }
}

struct EventRow: View {
    let event: Event
    let linkParser: LinkParser
    let onEventTap: (() -> Void)?

    @Environment(AppState.self)
    private var appState
    @Environment(\.design)
    private var design
    @State
    private var isHovered = false
    @State
    private var currentOverride: Int?

    /// Compound key for looking up this event's alert override.
    private var overrideKey: String {
        EventOverride.compoundKey(eventId: event.id, calendarId: event.calendarId)
    }

    init(event: Event, linkParser: LinkParser, onEventTap: (() -> Void)? = nil) {
        self.event = event
        self.linkParser = linkParser
        self.onEventTap = onEventTap
    }

    var body: some View {
        HStack(spacing: design.spacing.md) {
            VStack(alignment: .leading, spacing: design.spacing.xs) {
                HStack(spacing: design.spacing.xs) {
                    Text(event.title)
                        .font(design.fonts.callout)
                        .fontWeight(.medium)
                        .foregroundColor(design.colors.textPrimary)
                        .lineLimit(1)

                    if currentOverride != nil {
                        alertOverrideIndicator
                    }
                }

                HStack(spacing: design.spacing.xs) {
                    Image(systemName: "clock")
                        .foregroundColor(design.colors.accent)
                        .font(design.fonts.caption)
                        .fontWeight(.medium)

                    Text(event.startDate, style: .time)
                        .font(design.fonts.monoSmall)
                        .foregroundColor(design.colors.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: design.spacing.md) {
                if linkParser.isOnlineMeeting(event) {
                    Image(systemName: event.provider?.iconName ?? "link")
                        .foregroundColor(design.colors.accent)
                        .font(design.fonts.callout)
                        .fontWeight(.medium)
                }

                if linkParser.shouldShowJoinButton(for: event),
                   let primaryLink = linkParser.primaryLink(for: event)
                {
                    Button {
                        NSWorkspace.shared.open(primaryLink)
                    } label: {
                        Label("Join", systemImage: "video.fill")
                    }
                    .buttonStyle(UMButtonStyle(.secondary, size: .sm))
                }
            }
        }
        .padding(design.spacing.md)
        .background(
            isHovered ? design.colors.hover : Color.clear,
        )
        .umCard(.glass)
        .onHover { hovering in
            withAnimation(DesignAnimations.hover) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onEventTap?()
        }
        .contextMenu {
            alertOverrideMenu
        }
        .onChange(of: appState.alertOverrides[overrideKey]) { _, newValue in
            currentOverride = newValue
        }
        .onAppear {
            currentOverride = appState.alertOverrides[overrideKey]
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting: \(event.title) at \(event.startDate, style: .time)")
        .accessibilityIdentifier("event-row-\(event.id)")
        .accessibilityHint("Tap to view meeting details")
    }

    // MARK: - Alert Override Indicator

    @ViewBuilder
    private var alertOverrideIndicator: some View {
        if let override = currentOverride {
            if override == 0 {
                Image(systemName: "bell.slash.fill")
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textTertiary)
                    .accessibilityLabel("Alerts suppressed")
            } else {
                HStack(spacing: design.spacing.xs) {
                    Image(systemName: "bell.fill")
                        .font(design.fonts.caption)
                    Text("\(override)m")
                        .font(design.fonts.monoSmall)
                }
                .foregroundColor(design.colors.accent)
                .accessibilityLabel("Custom alert: \(override) minutes before")
            }
        }
    }

    // MARK: - Context Menu

    private var alertOverrideMenu: some View {
        Section("Alert Timing") {
            ForEach(AlertOverrideOption.allCases, id: \.label) { option in
                Button {
                    Task {
                        await appState.setAlertOverride(
                            for: event.id,
                            calendarId: event.calendarId,
                            minutes: option.minutes,
                        )
                        currentOverride = option.minutes
                    }
                } label: {
                    Label(option.label, systemImage: option.iconName)
                }
            }
        }
    }
}
