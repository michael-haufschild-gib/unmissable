import SwiftUI

struct OverlayContentView: View {
    let event: Event
    let onDismiss: () -> Void
    let onJoin: () -> Void
    let onSnooze: (Int) -> Void
    let isFromSnooze: Bool

    @EnvironmentObject
    private var preferences: PreferencesManager
    @Environment(\.customDesign)
    private var design
    @State
    private var timeUntilMeeting: TimeInterval = 0

    init(
        event: Event,
        onDismiss: @escaping () -> Void,
        onJoin: @escaping () -> Void,
        onSnooze: @escaping (Int) -> Void,
        isFromSnooze: Bool = false
    ) {
        self.event = event
        self.onDismiss = onDismiss
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.isFromSnooze = isFromSnooze
    }

    var body: some View {
        ZStack {
            // User-preference-driven background (respects theme + opacity slider)
            backgroundColor
                .ignoresSafeArea()

            // Radial glow behind content — the "beacon" effect
            RadialGradient(
                gradient: Gradient(colors: [
                    countdownColor.opacity(glowIntensity),
                    Color.clear,
                ]),
                center: .center,
                startRadius: 40,
                endRadius: 500 * fontScale
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.5), value: timeUntilMeeting < 60)

            VStack(spacing: 40 * fontScale) {
                overlayHeader
                meetingDetails
                countdownDisplay
                actionButtons

                if !preferences.minimalMode {
                    Text("Press ESC to dismiss")
                        .font(design.fonts.caption1)
                        .foregroundColor(subtleTextColor)
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .padding(.top, 20)
                }
            }
            .padding(40)
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
    }

    // MARK: - Body Sections

    private var overlayHeader: some View {
        VStack(spacing: 16 * fontScale) {
            Image(
                systemName: timeUntilMeeting > 0
                    ? "calendar.badge.clock" : "calendar.badge.exclamationmark"
            )
            .font(.system(size: 48 * fontScale, weight: .medium))
            .foregroundColor(timeUntilMeeting > 0 ? design.colors.accent : design.colors.warning)
            .shadow(
                color: (timeUntilMeeting > 0 ? design.colors.accent : design.colors.warning).opacity(0.4),
                radius: 20
            )

            Text(headerText)
                .font(.system(size: 28 * fontScale, weight: .medium))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundColor(subtleTextColor)
                .accessibilityIdentifier("overlay-header-text")
                .accessibilityLabel(headerText)
        }
    }

    private var meetingDetails: some View {
        VStack(spacing: 20 * fontScale) {
            Text(event.title)
                .font(.system(size: 48 * fontScale, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .accessibilityIdentifier("overlay-meeting-title")
                .accessibilityLabel("Meeting title: \(event.title)")

            if !preferences.minimalMode {
                if let organizer = event.organizer {
                    Text("with \(organizer)")
                        .font(.system(size: 24 * fontScale))
                        .foregroundColor(subtleTextColor)
                        .accessibilityLabel("Meeting organizer: \(organizer)")
                }
            }

            HStack(spacing: 16) {
                Image(systemName: "clock")
                    .foregroundColor(design.colors.accent)
                    .accessibilityHidden(true)
                Text(event.startDate, style: .time)
                    .font(.system(size: 28 * fontScale, weight: .medium, design: .monospaced))
                    .foregroundColor(textColor)
                    .accessibilityLabel(
                        "Meeting time: \(event.startDate.formatted(date: .omitted, time: .shortened))"
                    )
            }
        }
    }

    private var countdownDisplay: some View {
        VStack(spacing: 12 * fontScale) {
            if timeUntilMeeting > 0 {
                Text("Starting in")
                    .font(.system(size: 24 * fontScale))
                    .foregroundColor(subtleTextColor)
                    .accessibilityHidden(true)

                Text(formatTimeRemaining(timeUntilMeeting))
                    .font(.system(size: 88 * fontScale, weight: .bold, design: .monospaced))
                    .foregroundColor(countdownColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: formatTimeRemaining(timeUntilMeeting))
                    .accessibilityIdentifier("overlay-countdown")
                    .accessibilityLabel(
                        "Meeting starts in \(formatTimeRemainingForAccessibility(timeUntilMeeting))"
                    )
            } else if timeUntilMeeting > -300 {
                Text("Meeting Started")
                    .font(.system(size: 36 * fontScale, weight: .bold, design: .rounded))
                    .foregroundColor(design.colors.error)
                    .accessibilityIdentifier("overlay-meeting-started")
                    .accessibilityLabel("Meeting has started")

                Text(elapsedText)
                    .font(.system(size: 24 * fontScale, weight: .medium))
                    .foregroundColor(design.colors.warning)
                    .accessibilityLabel("Started \(elapsedText)")
            } else {
                Text("Running for")
                    .font(.system(size: 24 * fontScale))
                    .foregroundColor(subtleTextColor)
                    .accessibilityHidden(true)

                Text(formatTimeRunning(-timeUntilMeeting))
                    .font(.system(size: 48 * fontScale, weight: .bold, design: .monospaced))
                    .foregroundColor(design.colors.warning)
                    .accessibilityLabel(
                        "Meeting has been running for \(formatTimeRunningForAccessibility(-timeUntilMeeting))"
                    )
            }
        }
        .padding(.vertical, 20)
    }

    private var actionButtons: some View {
        HStack(spacing: 20) {
            if LinkParser.shared.isOnlineMeeting(event) {
                Button(action: onJoin) {
                    HStack(spacing: 10) {
                        Image(systemName: "video.fill")
                            .accessibilityHidden(true)
                        Text("Join Meeting")
                    }
                    .font(.system(size: 22 * fontScale, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(design.colors.textInverse)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(design.colors.accent)
                            .shadow(color: design.colors.accent.opacity(0.5), radius: 20, y: 8)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityIdentifier("overlay-join-button")
                .accessibilityLabel("Join meeting")
                .accessibilityHint("Opens the meeting link in your default application")
            }

            snoozeMenu

            Button("Dismiss") {
                onDismiss()
            }
            .font(.system(size: 18 * fontScale, weight: .medium))
            .tracking(0.5)
            .foregroundColor(subtleTextColor)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .stroke(subtleTextColor.opacity(0.3), lineWidth: 1)
            )
            .buttonStyle(ScaleButtonStyle())
            .accessibilityIdentifier("overlay-dismiss-button")
            .accessibilityLabel("Dismiss reminder")
            .accessibilityHint("Close this meeting reminder")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var snoozeMenu: some View {
        Menu {
            Button("1 minute") { onSnooze(1) }
                .accessibilityIdentifier("overlay-snooze-1")
                .accessibilityLabel("Snooze for 1 minute")
            Button("5 minutes") { onSnooze(5) }
                .accessibilityIdentifier("overlay-snooze-5")
                .accessibilityLabel("Snooze for 5 minutes")
            Button("10 minutes") { onSnooze(10) }
                .accessibilityIdentifier("overlay-snooze-10")
                .accessibilityLabel("Snooze for 10 minutes")
            Button("15 minutes") { onSnooze(15) }
                .accessibilityIdentifier("overlay-snooze-15")
                .accessibilityLabel("Snooze for 15 minutes")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge")
                    .accessibilityHidden(true)
                Text("Snooze")
            }
            .font(.system(size: 18 * fontScale, weight: .medium))
            .tracking(0.5)
            .foregroundColor(subtleTextColor)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .stroke(subtleTextColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityIdentifier("overlay-snooze-menu")
        .accessibilityLabel("Snooze reminder")
        .accessibilityHint("Postpone this reminder for a few minutes")
    }

    // MARK: - Computed Properties

    private var fontScale: Double {
        preferences.fontSize.scale
    }

    /// Human-readable elapsed time since meeting started, with correct grammar.
    private var elapsedText: String {
        let minutes = Int(-timeUntilMeeting / 60)
        switch minutes {
        case 0: return "just now"
        case 1: return "1 minute ago"
        default: return "\(minutes) minutes ago"
        }
    }

    private var headerText: String {
        if timeUntilMeeting > 0 {
            isFromSnooze ? "Snoozed Meeting Reminder" : "Upcoming Meeting"
        } else if timeUntilMeeting > -300 {
            isFromSnooze ? "Snoozed: Meeting in Progress" : "Meeting in Progress"
        } else {
            isFromSnooze ? "Snoozed: Ongoing Meeting" : "Ongoing Meeting"
        }
    }

    /// Background respects user's theme and opacity preferences
    private var backgroundColor: Color {
        switch preferences.appearanceTheme {
        case .light:
            Color.white.opacity(preferences.overlayOpacity)
        case .dark:
            Color.black.opacity(preferences.overlayOpacity)
        case .system:
            Color(.controlBackgroundColor).opacity(preferences.overlayOpacity)
        }
    }

    /// Primary text color driven by user's theme preference
    private var textColor: Color {
        switch preferences.appearanceTheme {
        case .light:
            .black
        case .dark:
            .white
        case .system:
            Color(.controlTextColor)
        }
    }

    /// Subtle/secondary text color for hints and labels
    private var subtleTextColor: Color {
        switch preferences.appearanceTheme {
        case .light:
            Color(red: 0.4, green: 0.4, blue: 0.42)
        case .dark:
            Color(red: 0.6, green: 0.6, blue: 0.63)
        case .system:
            Color(.secondaryLabelColor)
        }
    }

    /// Countdown color shifts from accent to error as meeting approaches
    private var countdownColor: Color {
        if timeUntilMeeting < 60 {
            design.colors.error
        } else {
            design.colors.accent
        }
    }

    /// Glow intensifies as meeting approaches — subtle ambient, not animated loop
    private var glowIntensity: Double {
        if timeUntilMeeting <= 0 { return 0.15 }
        if timeUntilMeeting < 60 { return 0.12 }
        if timeUntilMeeting < 300 { return 0.08 }
        return 0.05
    }

    // MARK: - Timer Management

    private func optimalTimerInterval() -> Duration {
        let absTime = abs(timeUntilMeeting)
        if absTime < 60 { return .seconds(1) }
        if absTime < 300 { return .seconds(5) }
        return .seconds(30)
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
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatTimeRunning(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        return String(format: "%d min", minutes)
    }

    private func formatTimeRemainingForAccessibility(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(abs(interval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            if seconds > 0 { return "\(minutes) minutes and \(seconds) seconds" }
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }

    private func formatTimeRunningForAccessibility(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

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

// MARK: - Button Styles

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
        links: [URL(string: "https://meet.google.com/abc-defg-hij")].compactMap(\.self)
    )

    OverlayContentView(
        event: sampleEvent,
        onDismiss: {},
        onJoin: {},
        onSnooze: { _ in },
        isFromSnooze: false
    )
    .environmentObject(PreferencesManager())
    .customThemedEnvironment()
}

#Preview("Overlay Content - Meeting Started") {
    let sampleEvent = Event(
        id: "preview-2",
        title: "Important Client Meeting",
        startDate: Date().addingTimeInterval(-120), // Started 2 minutes ago
        endDate: Date().addingTimeInterval(1800),
        organizer: "client@company.com",
        calendarId: "primary",
        links: [URL(string: "https://meet.google.com/xyz-uvwx-stu")].compactMap(\.self)
    )

    OverlayContentView(
        event: sampleEvent,
        onDismiss: {},
        onJoin: {},
        onSnooze: { _ in },
        isFromSnooze: false
    )
    .environmentObject(PreferencesManager())
    .customThemedEnvironment()
}

#Preview("Overlay Content - Snoozed Meeting Running") {
    let sampleEvent = Event(
        id: "preview-3",
        title: "Snoozed Team Meeting",
        startDate: Date().addingTimeInterval(-900),
        endDate: Date().addingTimeInterval(1800),
        organizer: "team@company.com",
        calendarId: "primary",
        links: [URL(string: "https://meet.google.com/xyz-uvwx-stu")].compactMap(\.self)
    )

    OverlayContentView(
        event: sampleEvent,
        onDismiss: {},
        onJoin: {},
        onSnooze: { _ in },
        isFromSnooze: true
    )
    .environmentObject(PreferencesManager())
    .customThemedEnvironment()
}
