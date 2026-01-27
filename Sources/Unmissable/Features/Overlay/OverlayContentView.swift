import Combine
import SwiftUI

struct OverlayContentView: View {
  let event: Event
  let onDismiss: () -> Void
  let onJoin: () -> Void
  let onSnooze: (Int) -> Void
  let isFromSnooze: Bool

  @EnvironmentObject private var preferences: PreferencesManager
  @State private var timeUntilMeeting: TimeInterval = 0
  @State private var timerCancellable: AnyCancellable?
  @State private var currentTimerInterval: TimeInterval = 1.0

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
      // Full-screen dark background with opacity from preferences
      backgroundColor
        .ignoresSafeArea()

      // Content
      VStack(spacing: 40 * fontScale) {
        // Header
        VStack(spacing: 16 * fontScale) {
          Image(
            systemName: timeUntilMeeting > 0
              ? "calendar.badge.clock" : "calendar.badge.exclamationmark"
          )
          .font(.system(size: 48 * fontScale))
          .foregroundColor(timeUntilMeeting > 0 ? .blue : .orange)

          Text(headerText)
            .font(.system(size: 36 * fontScale, weight: .bold))
            .foregroundColor(textColor)
            .accessibilityLabel(headerText)
        }

        // Meeting Details
        VStack(spacing: 20 * fontScale) {
          Text(event.title)
            .font(.system(size: 48 * fontScale, weight: .semibold))
            .foregroundColor(textColor)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .accessibilityLabel("Meeting title: \(event.title)")

          if !preferences.minimalMode {
            if let organizer = event.organizer {
              Text("with \(organizer)")
                .font(.system(size: 24 * fontScale))
                .foregroundColor(.gray)
                .accessibilityLabel("Meeting organizer: \(organizer)")
            }
          }

          HStack(spacing: 16) {
            Image(systemName: "clock")
              .foregroundColor(.blue)
              .accessibilityHidden(true)
            Text(event.startDate, style: .time)
              .font(.system(size: 28 * fontScale, weight: .medium))
              .foregroundColor(textColor)
              .accessibilityLabel(
                "Meeting time: \(event.startDate.formatted(date: .omitted, time: .shortened))")
          }
        }

        // Countdown Display
        VStack(spacing: 12 * fontScale) {
          if timeUntilMeeting > 0 {
            Text("Starting in")
              .font(.system(size: 24 * fontScale))
              .foregroundColor(.gray)
              .accessibilityHidden(true)

            Text(formatTimeRemaining(timeUntilMeeting))
              .font(.system(size: 88 * fontScale, weight: .bold, design: .monospaced))
              .foregroundColor(timeUntilMeeting < 60 ? .red : .blue)
              .animation(.easeInOut(duration: 0.3), value: timeUntilMeeting < 60)
              .accessibilityLabel(
                "Meeting starts in \(formatTimeRemainingForAccessibility(timeUntilMeeting))"
              )

          } else if timeUntilMeeting > -300 {
            Text("Meeting Started")
              .font(.system(size: 36 * fontScale, weight: .bold))
              .foregroundColor(.red)
              .accessibilityLabel("Meeting has started")

            Text("\(Int(-timeUntilMeeting / 60)) minutes ago")
              .font(.system(size: 24 * fontScale))
              .foregroundColor(.orange)
              .accessibilityLabel(
                "Started \(Int(-timeUntilMeeting / 60)) minutes ago")

          } else {
            Text("Running for")
              .font(.system(size: 24 * fontScale))
              .foregroundColor(.gray)
              .accessibilityHidden(true)

            Text(formatTimeRunning(-timeUntilMeeting))
              .font(.system(size: 48 * fontScale, weight: .bold))
              .foregroundColor(.orange)
              .accessibilityLabel(
                "Meeting has been running for \(formatTimeRunningForAccessibility(-timeUntilMeeting))"
              )
          }
        }
        .padding(.vertical, 20)

        // Action Buttons
        HStack(spacing: 24) {
          // Join Button (if available)
          if event.isOnlineMeeting {
            Button(action: onJoin) {
              HStack {
                Image(systemName: "video.fill")
                  .accessibilityHidden(true)
                Text("Join Meeting")
              }
              .font(.system(size: 24 * fontScale, weight: .semibold))
              .foregroundColor(.white)
              .padding(.horizontal, 32)
              .padding(.vertical, 16)
              .background(
                RoundedRectangle(cornerRadius: 12)
                  .fill(Color.blue)
              )
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Join meeting")
            .accessibilityHint("Opens the meeting link in your default application")
          }

          // Snooze Menu
          Menu {
            Button("1 minute") { onSnooze(1) }
              .accessibilityLabel("Snooze for 1 minute")
            Button("5 minutes") { onSnooze(5) }
              .accessibilityLabel("Snooze for 5 minutes")
            Button("10 minutes") { onSnooze(10) }
              .accessibilityLabel("Snooze for 10 minutes")
            Button("15 minutes") { onSnooze(15) }
              .accessibilityLabel("Snooze for 15 minutes")
          } label: {
            HStack {
              Image(systemName: "clock.badge")
                .accessibilityHidden(true)
              Text("Snooze")
            }
            .font(.system(size: 20 * fontScale, weight: .medium))
            .foregroundColor(textColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .stroke(textColor, lineWidth: 2)
            )
          }
          .buttonStyle(ScaleButtonStyle())
          .accessibilityLabel("Snooze reminder")
          .accessibilityHint("Postpone this reminder for a few minutes")

          // Dismiss Button
          Button("Dismiss") {
            onDismiss()
          }
          .font(.system(size: 20 * fontScale, weight: .medium))
          .foregroundColor(textColor)
          .padding(.horizontal, 24)
          .padding(.vertical, 12)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.gray, lineWidth: 2)
          )
          .buttonStyle(ScaleButtonStyle())
          .accessibilityLabel("Dismiss reminder")
          .accessibilityHint("Close this meeting reminder")
          .keyboardShortcut(.cancelAction)
        }

        // Keyboard shortcuts hint
        if !preferences.minimalMode {
          Text("Press ESC to dismiss")
            .font(.caption)
            .foregroundColor(.gray.opacity(0.7))
            .padding(.top, 20)
        }
      }
      .padding(40)
    }
    .onAppear {
      // Initialize timer on appear
      timeUntilMeeting = event.startDate.timeIntervalSinceNow
      startAdaptiveTimer()
    }
    .onDisappear {
      // Clean up timer
      timerCancellable?.cancel()
      timerCancellable = nil
    }
    .onKeyPress(.escape) {
      onDismiss()
      return .handled
    }
  }

  // MARK: - Computed Properties

  private var fontScale: Double {
    preferences.fontSize.scale
  }

  private var headerText: String {
    if timeUntilMeeting > 0 {
      return isFromSnooze ? "Snoozed Meeting Reminder" : "Upcoming Meeting"
    } else if timeUntilMeeting > -300 {
      return isFromSnooze ? "Snoozed: Meeting in Progress" : "Meeting in Progress"
    } else {
      return isFromSnooze ? "Snoozed: Ongoing Meeting" : "Ongoing Meeting"
    }
  }

  private var backgroundColor: Color {
    switch preferences.appearanceTheme {
    case .light:
      return Color.white.opacity(preferences.overlayOpacity)
    case .dark:
      return Color.black.opacity(preferences.overlayOpacity)
    case .system:
      return Color(.controlBackgroundColor).opacity(preferences.overlayOpacity)
    }
  }

  private var textColor: Color {
    switch preferences.appearanceTheme {
    case .light:
      return .black
    case .dark:
      return .white
    case .system:
      return Color(.controlTextColor)
    }
  }

  // MARK: - Timer Management

  /// Calculates the optimal timer interval based on time until meeting
  private func optimalTimerInterval() -> TimeInterval {
    let absTime = abs(timeUntilMeeting)
    if absTime < 60 {
      return 1.0  // Every second when < 1 minute
    } else if absTime < 300 {
      return 5.0  // Every 5 seconds when < 5 minutes
    } else {
      return 30.0  // Every 30 seconds otherwise
    }
  }

  /// Starts or restarts the timer with an adaptive interval
  private func startAdaptiveTimer() {
    timerCancellable?.cancel()
    let interval = optimalTimerInterval()
    currentTimerInterval = interval

    timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
      .autoconnect()
      .sink { [self] _ in
        timeUntilMeeting = event.startDate.timeIntervalSinceNow
        // Check if we need to switch to a different timer interval
        let newInterval = optimalTimerInterval()
        if newInterval != currentTimerInterval {
          startAdaptiveTimer()
        }
      }
  }

  // MARK: - Private Methods

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

    if hours > 0 {
      return String(format: "%dh %02dm", hours, minutes)
    } else {
      return String(format: "%d min", minutes)
    }
  }

  private func formatTimeRemainingForAccessibility(_ interval: TimeInterval) -> String {
    let totalSeconds = Int(abs(interval))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60

    if minutes > 0 {
      if seconds > 0 {
        return "\(minutes) minutes and \(seconds) seconds"
      } else {
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
      }
    } else {
      return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }
  }

  private func formatTimeRunningForAccessibility(_ interval: TimeInterval) -> String {
    let totalSeconds = Int(interval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60

    if hours > 0 {
      if minutes > 0 {
        return
          "\(hours) hour\(hours == 1 ? "" : "s") and \(minutes) minute\(minutes == 1 ? "" : "s")"
      } else {
        return "\(hours) hour\(hours == 1 ? "" : "s")"
      }
    } else {
      return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
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
    startDate: Date().addingTimeInterval(300),  // 5 minutes from now
    endDate: Date().addingTimeInterval(1200),
    organizer: "team-lead@company.com",
    calendarId: "primary",
    links: [URL(string: "https://meet.google.com/abc-defg-hij")!]
  )

  OverlayContentView(
    event: sampleEvent,
    onDismiss: {},
    onJoin: {},
    onSnooze: { _ in },
    isFromSnooze: false
  )
}

#Preview("Overlay Content - Meeting Started") {
  let sampleEvent = Event(
    id: "preview-2",
    title: "Important Client Meeting",
    startDate: Date().addingTimeInterval(-120),  // Started 2 minutes ago
    endDate: Date().addingTimeInterval(1800),
    organizer: "client@company.com",
    calendarId: "primary",
    links: [URL(string: "https://meet.google.com/xyz-uvwx-stu")!]
  )

  OverlayContentView(
    event: sampleEvent,
    onDismiss: {},
    onJoin: {},
    onSnooze: { _ in },
    isFromSnooze: false
  )
}

#Preview("Overlay Content - Snoozed Meeting Running") {
  let sampleEvent = Event(
    id: "preview-3",
    title: "Snoozed Team Meeting",
    startDate: Date().addingTimeInterval(-900),  // Started 15 minutes ago
    endDate: Date().addingTimeInterval(1800),
    organizer: "team@company.com",
    calendarId: "primary",
    links: [URL(string: "https://meet.google.com/xyz-uvwx-stu")!]
  )

  OverlayContentView(
    event: sampleEvent,
    onDismiss: {},
    onJoin: {},
    onSnooze: { _ in },
    isFromSnooze: true
  )
}
