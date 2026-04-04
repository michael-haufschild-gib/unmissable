import Accessibility
import SwiftUI

struct OverlayContentView: View {
    let event: Event
    let linkParser: LinkParser
    let onDismiss: () -> Void
    let onJoin: () -> Void
    let onSnooze: (Int) -> Void
    let isFromSnooze: Bool

    @Environment(PreferencesManager.self)
    private var preferences
    @Environment(ThemeManager.self)
    private var themeManager
    @Environment(\.design)
    private var design
    @State
    private var timeUntilMeeting: TimeInterval

    // MARK: - Layout Constants

    private static let gradientEndRadius: CGFloat = 500
    private static let iconScaleFactor: CGFloat = 2.0
    private static let titleScaleFactor: CGFloat = 2.0
    private static let countdownScaleFactor: CGFloat = 3.5
    private static let meetingStartedScaleFactor: CGFloat = 1.5
    private static let runningTimerScaleFactor: CGFloat = 2.0
    private static let shadowOpacity: Double = 0.4
    private static let accentShadowOpacity: Double = 0.5
    private static let borderOpacity: Double = 0.3
    private static let borderWidth: CGFloat = 1
    private static let buttonScalePressed: CGFloat = 0.95
    private static let buttonScaleNormal: CGFloat = 1.0
    private static let titleLineLimit = 3
    private static let timerFastSeconds = 1
    private static let timerMediumSeconds = 5
    private static let timerSlowSeconds = 30

    // MARK: - Timer Thresholds

    private static let urgentThresholdSeconds: TimeInterval = 60
    private static let recentStartThresholdSeconds: TimeInterval = -300
    private static let timerFastIntervalSeconds: TimeInterval = 60
    private static let timerMediumIntervalSeconds: TimeInterval = 300

    // MARK: - Glow Intensities

    private static let glowStarted: Double = 0.15
    private static let glowUrgent: Double = 0.12
    private static let glowSoon: Double = 0.08
    private static let glowDefault: Double = 0.05

    // MARK: - Snooze Durations

    private static let snoozeDuration1Min = 1
    private static let snoozeDuration5Min = 5
    private static let snoozeDuration10Min = 10
    private static let snoozeDuration15Min = 15

    // MARK: - Time Constants

    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600

    init(
        event: Event,
        linkParser: LinkParser,
        onDismiss: @escaping () -> Void,
        onJoin: @escaping () -> Void,
        onSnooze: @escaping (Int) -> Void,
        isFromSnooze: Bool = false,
    ) {
        self.event = event
        self.linkParser = linkParser
        self.onDismiss = onDismiss
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.isFromSnooze = isFromSnooze
        _timeUntilMeeting = State(initialValue: event.startDate.timeIntervalSinceNow)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            RadialGradient(
                gradient: Gradient(colors: [
                    countdownColor.opacity(glowIntensity),
                    Color.clear,
                ]),
                center: .center,
                startRadius: design.spacing.xxxl * fontScale,
                endRadius: Self.gradientEndRadius * fontScale,
            )
            .ignoresSafeArea()
            .animation(DesignAnimations.ambient, value: timeUntilMeeting < Self.urgentThresholdSeconds)

            VStack(spacing: design.spacing.xxxl * fontScale) {
                overlayHeader
                meetingDetails
                countdownDisplay
                actionButtons

                if !preferences.minimalMode {
                    Text("Press ESC to dismiss")
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textTertiary)
                        .tracking(DesignTracking.sectionLabel)
                        .textCase(.uppercase)
                        .padding(.top, design.spacing.xl)
                }
            }
            .padding(design.spacing.xxxl)
            .accessibilityIdentifier("overlay-content")
        }
        .task {
            timeUntilMeeting = event.startDate.timeIntervalSinceNow
            await runAdaptiveTimer()
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onAppear {
            let announcement = AccessibilityNotification.Announcement(
                "Meeting reminder overlay appeared for \(event.title)",
            )
            announcement.post()
        }
    }

    // MARK: - Body Sections

    private var overlayHeader: some View {
        VStack(spacing: design.spacing.lg * fontScale) {
            Image(
                systemName: timeUntilMeeting > 0
                    ? "calendar.badge.clock" : "calendar.badge.exclamationmark",
            )
            .font(design.fonts.title1)
            .scaleEffect(Self.iconScaleFactor * fontScale)
            .foregroundColor(timeUntilMeeting > 0 ? design.colors.accent : design.colors.warning)
            .shadow(
                color: (timeUntilMeeting > 0 ? design.colors.accent : design.colors.warning)
                    .opacity(Self.shadowOpacity),
                radius: design.shadows.glow.radius,
            )

            Text(headerText)
                .font(design.fonts.title2)
                .scaleEffect(fontScale)
                .tracking(DesignTracking.wider)
                .textCase(.uppercase)
                .foregroundColor(design.colors.textSecondary)
                .accessibilityIdentifier("overlay-header-text")
                .accessibilityLabel(headerText)
        }
    }

    private var meetingDetails: some View {
        VStack(spacing: design.spacing.xl * fontScale) {
            Text(event.title)
                .font(design.fonts.title1)
                .scaleEffect(Self.titleScaleFactor * fontScale)
                .foregroundColor(design.colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(Self.titleLineLimit)
                .accessibilityIdentifier("overlay-meeting-title")
                .accessibilityLabel("Meeting title: \(event.title)")

            if !preferences.minimalMode {
                if let organizer = event.organizer {
                    Text("with \(organizer)")
                        .font(design.fonts.title3)
                        .scaleEffect(fontScale)
                        .foregroundColor(design.colors.textSecondary)
                        .accessibilityLabel("Meeting organizer: \(organizer)")
                }
            }

            HStack(spacing: design.spacing.lg) {
                Image(systemName: "clock")
                    .foregroundColor(design.colors.accent)
                    .accessibilityHidden(true)
                Text(event.startDate, style: .time)
                    .font(design.fonts.title2)
                    .fontDesign(.monospaced)
                    .scaleEffect(fontScale)
                    .foregroundColor(design.colors.textPrimary)
                    .accessibilityLabel(
                        "Meeting time: \(event.startDate.formatted(date: .omitted, time: .shortened))",
                    )
            }
        }
    }

    private var countdownDisplay: some View {
        VStack(spacing: design.spacing.md * fontScale) {
            if timeUntilMeeting > 0 {
                Text("Starting in")
                    .font(design.fonts.title3)
                    .scaleEffect(fontScale)
                    .foregroundColor(design.colors.textSecondary)
                    .accessibilityHidden(true)

                Text(formatTimeRemaining(timeUntilMeeting))
                    .font(design.fonts.title1)
                    .fontDesign(.monospaced)
                    .fontWeight(.bold)
                    .scaleEffect(Self.countdownScaleFactor * fontScale)
                    .foregroundColor(countdownColor)
                    .contentTransition(.numericText())
                    .animation(DesignAnimations.content, value: formatTimeRemaining(timeUntilMeeting))
                    .accessibilityIdentifier("overlay-countdown")
                    .accessibilityLabel(
                        "Meeting starts in \(formatTimeRemainingForAccessibility(timeUntilMeeting))",
                    )
            } else if timeUntilMeeting > Self.recentStartThresholdSeconds {
                Text("Meeting Started")
                    .font(design.fonts.title1)
                    .fontWeight(.bold)
                    .scaleEffect(Self.meetingStartedScaleFactor * fontScale)
                    .foregroundColor(design.colors.error)
                    .accessibilityIdentifier("overlay-meeting-started")
                    .accessibilityLabel("Meeting has started")

                Text(elapsedText)
                    .font(design.fonts.title3)
                    .scaleEffect(fontScale)
                    .foregroundColor(design.colors.warning)
                    .accessibilityLabel("Started \(elapsedText)")
            } else {
                Text("Running for")
                    .font(design.fonts.title3)
                    .scaleEffect(fontScale)
                    .foregroundColor(design.colors.textSecondary)
                    .accessibilityHidden(true)

                Text(formatTimeRunning(-timeUntilMeeting))
                    .font(design.fonts.title1)
                    .fontDesign(.monospaced)
                    .fontWeight(.bold)
                    .scaleEffect(Self.runningTimerScaleFactor * fontScale)
                    .foregroundColor(design.colors.warning)
                    .accessibilityLabel(
                        "Meeting has been running for \(formatTimeRunningForAccessibility(-timeUntilMeeting))",
                    )
            }
        }
        .padding(.vertical, design.spacing.xl)
    }

    private var actionButtons: some View {
        HStack(spacing: design.spacing.xl) {
            if linkParser.isOnlineMeeting(event) {
                Button(action: onJoin) {
                    HStack(spacing: design.spacing.md) {
                        Image(systemName: "video.fill")
                            .accessibilityHidden(true)
                        Text("Join Meeting")
                    }
                    .font(design.fonts.title3)
                    .scaleEffect(fontScale)
                    .tracking(DesignTracking.wide)
                    .foregroundColor(design.colors.textInverse)
                    .padding(.horizontal, design.spacing.xxxl)
                    .padding(.vertical, design.spacing.lg)
                    .background(
                        Capsule()
                            .fill(design.colors.accent)
                            .shadow(
                                color: design.colors.accent.opacity(Self.accentShadowOpacity),
                                radius: design.shadows.glow.radius,
                                y: design.spacing.sm,
                            ),
                    )
                }
                .buttonStyle(OverlayScaleButtonStyle())
                .accessibilityIdentifier("overlay-join-button")
                .accessibilityLabel("Join meeting")
                .accessibilityHint("Opens the meeting link in your default application")
            }

            if preferences.allowSnooze {
                snoozeMenu
            }

            Button("Dismiss") {
                onDismiss()
            }
            .font(design.fonts.headline)
            .scaleEffect(fontScale)
            .tracking(DesignTracking.wide)
            .foregroundColor(design.colors.textSecondary)
            .padding(.horizontal, design.spacing.xxl)
            .padding(.vertical, design.spacing.md)
            .background(
                Capsule()
                    .stroke(
                        design.colors.textSecondary.opacity(Self.borderOpacity),
                        lineWidth: Self.borderWidth,
                    ),
            )
            .buttonStyle(OverlayScaleButtonStyle())
            .accessibilityIdentifier("overlay-dismiss-button")
            .accessibilityLabel("Dismiss reminder")
            .accessibilityHint("Close this meeting reminder")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var snoozeMenu: some View {
        Menu {
            Button("1 minute") { onSnooze(Self.snoozeDuration1Min) }
                .accessibilityIdentifier("overlay-snooze-1")
                .accessibilityLabel("Snooze for 1 minute")
            Button("5 minutes") { onSnooze(Self.snoozeDuration5Min) }
                .accessibilityIdentifier("overlay-snooze-5")
                .accessibilityLabel("Snooze for 5 minutes")
            Button("10 minutes") { onSnooze(Self.snoozeDuration10Min) }
                .accessibilityIdentifier("overlay-snooze-10")
                .accessibilityLabel("Snooze for 10 minutes")
            Button("15 minutes") { onSnooze(Self.snoozeDuration15Min) }
                .accessibilityIdentifier("overlay-snooze-15")
                .accessibilityLabel("Snooze for 15 minutes")
        } label: {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: "clock.badge")
                    .accessibilityHidden(true)
                Text("Snooze")
            }
            .font(design.fonts.headline)
            .scaleEffect(fontScale)
            .tracking(DesignTracking.wide)
            .foregroundColor(design.colors.textSecondary)
            .padding(.horizontal, design.spacing.xxl)
            .padding(.vertical, design.spacing.md)
            .background(
                Capsule()
                    .stroke(
                        design.colors.textSecondary.opacity(Self.borderOpacity),
                        lineWidth: Self.borderWidth,
                    ),
            )
        }
        .buttonStyle(OverlayScaleButtonStyle())
        .accessibilityIdentifier("overlay-snooze-menu")
        .accessibilityLabel("Snooze reminder")
        .accessibilityHint("Postpone this reminder for a few minutes")
    }

    // MARK: - Computed Properties

    private var fontScale: Double {
        preferences.fontSize.scale
    }

    private var elapsedText: String {
        let minutes = Int(-timeUntilMeeting / Double(Self.secondsPerMinute))
        switch minutes {
        case 0: return "just now"
        case 1: return "1 minute ago"
        default: return "\(minutes) minutes ago"
        }
    }

    private var headerText: String {
        if timeUntilMeeting > 0 {
            isFromSnooze ? "Snoozed Meeting Reminder" : "Upcoming Meeting"
        } else if timeUntilMeeting > Self.recentStartThresholdSeconds {
            isFromSnooze ? "Snoozed: Meeting in Progress" : "Meeting in Progress"
        } else {
            isFromSnooze ? "Snoozed: Ongoing Meeting" : "Ongoing Meeting"
        }
    }

    private var backgroundColor: Color {
        themeManager.resolvedTheme.isDark
            ? Color.black.opacity(preferences.overlayOpacity)
            : Color.white.opacity(preferences.overlayOpacity)
    }

    private var countdownColor: Color {
        if timeUntilMeeting < Self.urgentThresholdSeconds {
            design.colors.error
        } else {
            design.colors.accent
        }
    }

    private var glowIntensity: Double {
        if timeUntilMeeting <= 0 { return Self.glowStarted }
        if timeUntilMeeting < Self.urgentThresholdSeconds { return Self.glowUrgent }
        if timeUntilMeeting < Self.timerMediumIntervalSeconds { return Self.glowSoon }
        return Self.glowDefault
    }

    // MARK: - Timer Management

    private func optimalTimerInterval() -> Duration {
        let absTime = abs(timeUntilMeeting)
        if absTime < Self.timerFastIntervalSeconds { return .seconds(Self.timerFastSeconds) }
        if absTime < Self.timerMediumIntervalSeconds { return .seconds(Self.timerMediumSeconds) }
        return .seconds(Self.timerSlowSeconds)
    }

    private func runAdaptiveTimer() async {
        while !Task.isCancelled {
            let interval = optimalTimerInterval()
            do {
                try await Task.sleep(for: interval)
            } catch {
                break
            }
            timeUntilMeeting = event.startDate.timeIntervalSinceNow
        }
    }

    // MARK: - Formatting

    private func formatTimeRemaining(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(abs(interval))
        let minutes = totalSeconds / Self.secondsPerMinute
        let seconds = totalSeconds % Self.secondsPerMinute
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatTimeRunning(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / Self.secondsPerHour
        let minutes = (totalSeconds % Self.secondsPerHour) / Self.secondsPerMinute

        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        return String(format: "%d min", minutes)
    }

    private func formatTimeRemainingForAccessibility(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(abs(interval))
        let minutes = totalSeconds / Self.secondsPerMinute
        let seconds = totalSeconds % Self.secondsPerMinute

        if minutes > 0 {
            if seconds > 0 { return "\(minutes) minutes and \(seconds) seconds" }
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }

    private func formatTimeRunningForAccessibility(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / Self.secondsPerHour
        let minutes = (totalSeconds % Self.secondsPerHour) / Self.secondsPerMinute

        if hours > 0 {
            if minutes > 0 {
                return
                    "\(hours) hour\(hours == 1 ? "" : "s") and \(minutes) minute\(minutes == 1 ? "" : "s")"
            }
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}

// MARK: - Overlay Button Style

/// Scale-on-press style for overlay buttons (these are special full-screen context,
/// not using UMButtonStyle because they have custom capsule/stroke styling).
struct OverlayScaleButtonStyle: ButtonStyle {
    private static let scalePressed: CGFloat = 0.95
    private static let scaleNormal: CGFloat = 1.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.scalePressed : Self.scaleNormal)
            .animation(DesignAnimations.press, value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Overlay Content - Before Meeting") {
    let sampleEvent = Event(
        id: "preview-1",
        title: "Daily Team Standup with Engineering Team",
        startDate: Date().addingTimeInterval(300),
        endDate: Date().addingTimeInterval(1200),
        organizer: "team-lead@company.com",
        calendarId: "primary",
        links: [URL(string: "https://meet.google.com/abc-defg-hij")].compactMap(\.self),
    )

    let themeManager = ThemeManager()

    OverlayContentView(
        event: sampleEvent,
        linkParser: LinkParser(),
        onDismiss: {},
        onJoin: {},
        onSnooze: { _ in },
        isFromSnooze: false,
    )
    .environment(PreferencesManager(themeManager: themeManager))
    .themed(themeManager: themeManager)
}

#Preview("Overlay Content - Meeting Started") {
    let sampleEvent = Event(
        id: "preview-2",
        title: "Important Client Meeting",
        startDate: Date().addingTimeInterval(-120),
        endDate: Date().addingTimeInterval(1800),
        organizer: "client@company.com",
        calendarId: "primary",
        links: [URL(string: "https://meet.google.com/xyz-uvwx-stu")].compactMap(\.self),
    )

    let themeManager = ThemeManager()

    OverlayContentView(
        event: sampleEvent,
        linkParser: LinkParser(),
        onDismiss: {},
        onJoin: {},
        onSnooze: { _ in },
        isFromSnooze: false,
    )
    .environment(PreferencesManager(themeManager: themeManager))
    .themed(themeManager: themeManager)
}

#Preview("Overlay Content - Snoozed Meeting Running") {
    let sampleEvent = Event(
        id: "preview-3",
        title: "Snoozed Team Meeting",
        startDate: Date().addingTimeInterval(-900),
        endDate: Date().addingTimeInterval(1800),
        organizer: "team@company.com",
        calendarId: "primary",
        links: [URL(string: "https://meet.google.com/xyz-uvwx-stu")].compactMap(\.self),
    )

    let themeManager = ThemeManager()

    OverlayContentView(
        event: sampleEvent,
        linkParser: LinkParser(),
        onDismiss: {},
        onJoin: {},
        onSnooze: { _ in },
        isFromSnooze: true,
    )
    .environment(PreferencesManager(themeManager: themeManager))
    .themed(themeManager: themeManager)
}
