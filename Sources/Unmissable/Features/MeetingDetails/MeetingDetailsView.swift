import SwiftUI

struct MeetingDetailsView: View {
    let event: Event
    let onClose: () -> Void
    /// Per-event alert override in minutes, or `nil` if using default timing.
    let alertOverrideMinutes: Int?
    @Environment(\.design)
    private var design
    @EnvironmentObject
    private var themeManager: ThemeManager

    init(event: Event, onClose: @escaping () -> Void, alertOverrideMinutes: Int? = nil) {
        self.event = event
        self.onClose = onClose
        self.alertOverrideMinutes = alertOverrideMinutes
    }

    private static let headerBorderHeight: CGFloat = 1
    private static let descriptionMinHeight: CGFloat = 60
    private static let descriptionMaxHeight: CGFloat = 150
    private static let participantsMaxHeight: CGFloat = 200
    private static let attendeeNameSpacing: CGFloat = 2
    private static let organizerBadgeVerticalPadding: CGFloat = 2
    private static let organizerBadgeBackgroundOpacity: Double = 0.1
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600
    private static let titleLineLimit = 2
    private static let locationLineLimit = 3

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and close button
            headerSection

            // Scrollable content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: design.spacing.lg) {
                    // Basic meeting info
                    meetingInfoSection

                    // Description section
                    if let description = event.description, !description.isEmpty {
                        descriptionSection(description)
                    } else {
                        emptyDescriptionSection
                    }

                    // Participants section
                    if !event.attendees.isEmpty {
                        participantsSection
                    } else {
                        emptyParticipantsSection
                    }

                    // Meeting links section
                    if !event.links.isEmpty {
                        meetingLinksSection
                    }
                }
                .padding(design.spacing.lg)
            }
        }
        .background(design.colors.background)
        .clipShape(RoundedRectangle(cornerRadius: design.corners.lg))
        .shadow(
            color: design.shadows.soft.color,
            radius: design.shadows.soft.radius,
            x: design.shadows.soft.x,
            y: design.shadows.soft.y,
        )
        .frame(
            width: MeetingDetailsLayout.popupSize.width,
            height: MeetingDetailsLayout.popupSize.height,
        )
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: design.spacing.xs) {
                Text("Meeting Details")
                    .font(design.fonts.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(design.colors.textPrimary)

                Text(event.title)
                    .font(design.fonts.callout)
                    .fontWeight(.medium)
                    .foregroundColor(design.colors.textSecondary)
                    .lineLimit(Self.titleLineLimit)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(UMButtonStyle(.ghost, size: .icon))
        }
        .padding(design.spacing.lg)
        .background(design.colors.background)
        .overlay(
            Rectangle()
                .fill(design.colors.borderSubtle)
                .frame(height: Self.headerBorderHeight),
            alignment: .bottom,
        )
        .contentShape(Rectangle())
        // Empty gesture prevents taps from falling through to the scrollable
        // content below the fixed header, which would trigger link navigation.
        .onTapGesture {}
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Meeting Info Section

    private var meetingInfoSection: some View {
        VStack(alignment: .leading, spacing: design.spacing.md) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: "calendar")
                    .foregroundColor(design.colors.accent)
                    .font(design.fonts.body)
                    .fontWeight(.medium)

                Text("When")
                    .font(design.fonts.callout)
                    .fontWeight(.medium)
                    .foregroundColor(design.colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: design.spacing.xs) {
                Text(event.startDate, style: .date)
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textSecondary)

                if !event.isAllDay {
                    HStack(spacing: design.spacing.sm) {
                        Text(event.startDate, style: .time)
                            .font(design.fonts.callout)
                            .foregroundColor(design.colors.textSecondary)

                        Text("–")
                            .foregroundColor(design.colors.textTertiary)

                        Text(event.endDate, style: .time)
                            .font(design.fonts.callout)
                            .foregroundColor(design.colors.textSecondary)
                    }

                    Text(formatDuration(event.duration))
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textTertiary)
                }
            }

            if let location = event.location, !location.isEmpty {
                VStack(alignment: .leading, spacing: design.spacing.xs) {
                    HStack(spacing: design.spacing.sm) {
                        Image(systemName: "location")
                            .foregroundColor(design.colors.accent)
                            .font(design.fonts.body)
                            .fontWeight(.medium)

                        Text("Location")
                            .font(design.fonts.callout)
                            .fontWeight(.medium)
                            .foregroundColor(design.colors.textPrimary)
                    }

                    Text(location)
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textSecondary)
                        .lineLimit(Self.locationLineLimit)
                }
                .padding(.top, design.spacing.sm)
            }

            // Alert timing info
            alertTimingSection
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .umCard(.flat)
    }

    @ViewBuilder
    private var alertTimingSection: some View {
        let hasOverride = alertOverrideMinutes != nil
        VStack(alignment: .leading, spacing: design.spacing.xs) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: hasOverride ? "bell.badge" : "bell")
                    .foregroundColor(design.colors.accent)
                    .font(design.fonts.body)
                    .fontWeight(.medium)

                Text("Alert")
                    .font(design.fonts.callout)
                    .fontWeight(.medium)
                    .foregroundColor(design.colors.textPrimary)
            }

            Text(alertTimingLabel)
                .font(design.fonts.callout)
                .foregroundColor(design.colors.textSecondary)
        }
        .padding(.top, design.spacing.sm)
    }

    private var alertTimingLabel: String {
        guard let override = alertOverrideMinutes else {
            return "Default timing"
        }
        if override == 0 {
            return "Alerts suppressed"
        }
        return "\(override) minute\(override == 1 ? "" : "s") before"
    }

    // MARK: - Description Section

    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: design.spacing.md) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: "text.alignleft")
                    .foregroundColor(design.colors.accent)
                    .font(design.fonts.body)
                    .fontWeight(.medium)

                Text("Description")
                    .font(design.fonts.callout)
                    .fontWeight(.medium)
                    .foregroundColor(design.colors.textPrimary)
            }

            // HTML Content container with proper sizing
            VStack(alignment: .leading, spacing: 0) {
                HTMLTextView(
                    htmlContent: description,
                    resolvedTheme: themeManager.resolvedTheme,
                    onLinkTap: { url in
                        NSWorkspace.shared.open(url)
                    },
                )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: Self.descriptionMinHeight,
                maxHeight: Self.descriptionMaxHeight,
                alignment: Alignment.topLeading,
            )
            .padding(.vertical, design.spacing.xs)
            .background(design.colors.background)
            .clipShape(RoundedRectangle(cornerRadius: design.corners.sm))

            // Show attachments if available
            if !event.attachments.isEmpty {
                AttachmentsView(attachments: event.attachments)
                    .padding(.top, design.spacing.sm)
            }
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .umCard(.flat)
    }

    private var emptyDescriptionSection: some View {
        HStack(spacing: design.spacing.sm) {
            Image(systemName: "text.alignleft")
                .foregroundColor(design.colors.textTertiary)
                .font(design.fonts.body)

            Text("No description available")
                .font(design.fonts.callout)
                .foregroundColor(design.colors.textTertiary)
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .umCard(.flat)
    }

    // MARK: - Participants Section

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: design.spacing.md) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: "person.2")
                    .foregroundColor(design.colors.accent)
                    .font(design.fonts.body)
                    .fontWeight(.medium)

                Text("Participants (\(event.attendees.count))")
                    .font(design.fonts.callout)
                    .fontWeight(.medium)
                    .foregroundColor(design.colors.textPrimary)
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: design.spacing.sm) {
                    ForEach(event.attendees) { attendee in
                        attendeeRow(attendee)
                    }
                }
                .padding(.vertical, design.spacing.xs)
            }
            .frame(maxHeight: Self.participantsMaxHeight)
            .background(design.colors.background)
            .clipShape(RoundedRectangle(cornerRadius: design.corners.sm))
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .umCard(.flat)
    }

    private var emptyParticipantsSection: some View {
        HStack(spacing: design.spacing.sm) {
            Image(systemName: "person.2")
                .foregroundColor(design.colors.textTertiary)
                .font(design.fonts.body)

            Text("Participant information unavailable")
                .font(design.fonts.callout)
                .foregroundColor(design.colors.textTertiary)
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .umCard(.flat)
    }

    private func attendeeRow(_ attendee: Attendee) -> some View {
        HStack(spacing: design.spacing.sm) {
            if let status = attendee.status {
                Image(systemName: status.iconName)
                    .foregroundColor(statusColor(for: status))
                    .font(design.fonts.footnote)
                    .fontWeight(.medium)
            }

            VStack(alignment: .leading, spacing: Self.attendeeNameSpacing) {
                Text(attendee.displayName)
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)
                    .lineLimit(1)

                if attendee.name != nil, attendee.name != attendee.email {
                    Text(attendee.email)
                        .font(design.fonts.caption)
                        .foregroundColor(design.colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if attendee.isOrganizer {
                Text("Organizer")
                    .font(design.fonts.caption)
                    .fontWeight(.medium)
                    .foregroundColor(design.colors.accent)
                    .padding(.horizontal, design.spacing.sm)
                    .padding(.vertical, Self.organizerBadgeVerticalPadding)
                    .background(design.colors.accent.opacity(Self.organizerBadgeBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: design.corners.sm))
            } else if attendee.isOptional {
                Text("Optional")
                    .font(design.fonts.caption)
                    .foregroundColor(design.colors.textTertiary)
            }
        }
        .padding(.horizontal, design.spacing.sm)
        .padding(.vertical, design.spacing.xs)
    }

    // MARK: - Meeting Links Section

    private var meetingLinksSection: some View {
        VStack(alignment: .leading, spacing: design.spacing.md) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: "link")
                    .foregroundColor(design.colors.accent)
                    .font(design.fonts.body)
                    .fontWeight(.medium)

                Text("Join Meeting")
                    .font(design.fonts.callout)
                    .fontWeight(.medium)
                    .foregroundColor(design.colors.textPrimary)
            }

            VStack(spacing: design.spacing.sm) {
                ForEach(event.links, id: \.absoluteString) { link in
                    let linkProvider = Provider.detect(from: link)
                    Button {
                        NSWorkspace.shared.open(link)
                    } label: {
                        Label(
                            "Join via \(linkProvider.displayName)",
                            systemImage: linkProvider.iconName,
                        )
                    }
                    .buttonStyle(UMButtonStyle(.primary))
                }
            }
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .umCard(.flat)
    }

    // MARK: - Helper Methods

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / Self.secondsPerHour
        let minutes = (Int(duration) % Self.secondsPerHour) / Self.secondsPerMinute

        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func statusColor(for status: AttendeeStatus) -> Color {
        switch status {
        case .accepted:
            design.colors.success

        case .declined:
            design.colors.error

        case .tentative:
            design.colors.warning

        case .needsAction:
            design.colors.textTertiary
        }
    }
}

private enum MeetingDetailsPreviewConstants {
    static let halfHourSeconds: TimeInterval = 1800
}

#Preview {
    let sampleEvent = Event(
        id: "sample",
        title: "Team Standup Meeting",
        startDate: Date(),
        endDate: Date().addingTimeInterval(MeetingDetailsPreviewConstants.halfHourSeconds),
        organizer: "manager@company.com",
        description:
        "Daily standup to discuss progress and blockers. Please come prepared with your updates.",
        location: "Conference Room A",
        attendees: [
            Attendee(
                name: "John Doe",
                email: "john@company.com",
                status: .accepted,
                isOrganizer: true,
                isSelf: false,
            ),
            Attendee(
                name: "Jane Smith",
                email: "jane@company.com",
                status: .tentative,
                isSelf: false,
            ),
            Attendee(
                email: "contractor@external.com",
                status: .needsAction,
                isOptional: true,
                isSelf: false,
            ),
        ],
        calendarId: "primary",
        links: [URL(string: "https://meet.google.com/abc-defg-hij")].compactMap(\.self),
    )

    MeetingDetailsView(event: sampleEvent, onClose: {})
        .themed(themeManager: ThemeManager())
}
