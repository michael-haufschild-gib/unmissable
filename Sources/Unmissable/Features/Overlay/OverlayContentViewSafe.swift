import Foundation
import SwiftUI

/// Environment-independent overlay content view that doesn't depend on @EnvironmentObject
/// This eliminates the crash when creating NSHostingView without proper environment setup
struct OverlayContentViewSafe: View {
    let event: Event
    let onDismiss: () -> Void
    let onJoin: () -> Void
    let onSnooze: (Int) -> Void

    // Injected dependencies instead of environment objects
    let overlayOpacity: Double
    let appearanceTheme: AppTheme
    let customDesign: CustomDesign

    var body: some View {
        ZStack {
            // Full-screen background with injected opacity
            backgroundColor
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Centered content
            VStack(spacing: customDesign.spacing.lg) {
                // Event info card
                CustomCard(style: .elevated) {
                    VStack(alignment: .leading, spacing: customDesign.spacing.md) {
                        // Meeting title
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(customDesign.colors.accent)
                                .font(.system(size: 18, weight: .medium))

                            Text(event.title.isEmpty ? "Untitled Meeting" : event.title)
                                .font(customDesign.fonts.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(customDesign.colors.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()
                        }

                        // Meeting time info
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(customDesign.colors.textSecondary)
                                .font(.system(size: 14, weight: .medium))

                            Text("Starts \(formatEventTime(event.startDate))")
                                .font(customDesign.fonts.body)
                                .foregroundColor(customDesign.colors.textSecondary)

                            Spacer()
                        }

                        // Organizer info if available
                        if let organizer = event.organizer, !organizer.isEmpty {
                            HStack {
                                Image(systemName: "person")
                                    .foregroundColor(customDesign.colors.textSecondary)
                                    .font(.system(size: 14, weight: .medium))

                                Text(organizer)
                                    .font(customDesign.fonts.callout)
                                    .foregroundColor(customDesign.colors.textSecondary)
                                    .lineLimit(1)

                                Spacer()
                            }
                        }
                    }
                    .padding(customDesign.spacing.lg)
                }

                // Action buttons
                HStack(spacing: customDesign.spacing.md) {
                    // Dismiss button
                    CustomButton("Dismiss", style: .secondary) {
                        onDismiss()
                    }

                    // Join button (only if meeting has links)
                    if !event.links.isEmpty {
                        CustomButton("Join Meeting", style: .primary) {
                            onJoin()
                        }
                    }
                }

                // Snooze options
                HStack(spacing: customDesign.spacing.sm) {
                    ForEach([1, 5, 10, 15], id: \.self) { minutes in
                        CustomButton("\(minutes)m", style: .minimal) {
                            onSnooze(minutes)
                        }
                    }
                }

                Text("Snooze for:")
                    .font(customDesign.fonts.caption1)
                    .foregroundColor(customDesign.colors.textSecondary)
            }
            .padding(customDesign.spacing.xl)
            .frame(maxWidth: 500)
        }
    }

    private var backgroundColor: Color {
        switch appearanceTheme {
        case .light:
            Color.white.opacity(overlayOpacity)
        case .dark:
            Color.black.opacity(overlayOpacity)
        case .system:
            Color(.controlBackgroundColor).opacity(overlayOpacity)
        }
    }

    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let testEvent = Event(
        id: "test",
        title: "Test Meeting",
        startDate: Date().addingTimeInterval(300),
        endDate: Date().addingTimeInterval(3600),
        organizer: "test@example.com",
        calendarId: "test"
    )

    OverlayContentViewSafe(
        event: testEvent,
        onDismiss: {},
        onJoin: {},
        onSnooze: { _ in },
        overlayOpacity: 0.95,
        appearanceTheme: .system,
        customDesign: CustomDesign.design(for: .dark)
    )
}
