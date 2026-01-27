import SwiftUI

struct MeetingDetailsView: View {
    let event: Event
    @Environment(\.customDesign) private var design
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared

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
        .cornerRadius(design.corners.large)
        .shadow(
            color: design.shadows.color, radius: design.shadows.radius, x: design.shadows.offset.width,
            y: design.shadows.offset.height
        )
        .frame(width: 480, height: 600)
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
                    .font(design.fonts.subheadline)
                    .foregroundColor(design.colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            CustomButton("", icon: "xmark", style: .minimal) {
                dismiss()
            }
        }
        .padding(design.spacing.lg)
        .background(design.colors.background)
        .overlay(
            Rectangle()
                .fill(design.colors.divider)
                .frame(height: 1),
            alignment: .bottom
        )
        .contentShape(Rectangle()) // Make entire header area draggable
        .onTapGesture {} // Enable tap handling for window dragging
    }

    // MARK: - Meeting Info Section

    private var meetingInfoSection: some View {
        VStack(alignment: .leading, spacing: design.spacing.md) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: "calendar")
                    .foregroundColor(design.colors.accent)
                    .font(.system(size: 16, weight: .medium))

                Text("When")
                    .font(design.fonts.subheadline)
                    .fontWeight(.semibold)
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
                        .font(design.fonts.caption1)
                        .foregroundColor(design.colors.textTertiary)
                }
            }

            if let location = event.location, !location.isEmpty {
                VStack(alignment: .leading, spacing: design.spacing.xs) {
                    HStack(spacing: design.spacing.sm) {
                        Image(systemName: "location")
                            .foregroundColor(design.colors.accent)
                            .font(.system(size: 16, weight: .medium))

                        Text("Location")
                            .font(design.fonts.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(design.colors.textPrimary)
                    }

                    Text(location)
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textSecondary)
                        .lineLimit(3)
                }
                .padding(.top, design.spacing.sm)
            }
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(design.colors.backgroundSecondary)
        .cornerRadius(design.corners.medium)
    }

    // MARK: - Description Section

    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: design.spacing.md) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: "text.alignleft")
                    .foregroundColor(design.colors.accent)
                    .font(.system(size: 16, weight: .medium))

                Text("Description")
                    .font(design.fonts.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(design.colors.textPrimary)
            }

            // HTML Content container with proper sizing
            VStack(alignment: .leading, spacing: 0) {
                HTMLTextView(
                    htmlContent: description,
                    effectiveTheme: themeManager.effectiveTheme,
                    onLinkTap: { url in
                        NSWorkspace.shared.open(url)
                    }
                )
            }
            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 150, alignment: Alignment.topLeading)
            .padding(.vertical, design.spacing.xs)
            .background(design.colors.background)
            .cornerRadius(design.corners.small)

            // Show attachments if available
            if !event.attachments.isEmpty {
                AttachmentsView(attachments: event.attachments)
                    .padding(.top, design.spacing.sm)
            }
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(design.colors.backgroundSecondary)
        .cornerRadius(design.corners.medium)
    }

    private var emptyDescriptionSection: some View {
        HStack(spacing: design.spacing.sm) {
            Image(systemName: "text.alignleft")
                .foregroundColor(design.colors.textTertiary)
                .font(.system(size: 16))

            Text("No description available")
                .font(design.fonts.callout)
                .foregroundColor(design.colors.textTertiary)
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(design.colors.backgroundSecondary)
        .cornerRadius(design.corners.medium)
    }

    // MARK: - Participants Section

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: design.spacing.md) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: "person.2")
                    .foregroundColor(design.colors.accent)
                    .font(.system(size: 16, weight: .medium))

                Text("Participants (\(event.attendees.count))")
                    .font(design.fonts.subheadline)
                    .fontWeight(.semibold)
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
            .frame(maxHeight: 200)
            .background(design.colors.background)
            .cornerRadius(design.corners.small)
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(design.colors.backgroundSecondary)
        .cornerRadius(design.corners.medium)
    }

    private var emptyParticipantsSection: some View {
        HStack(spacing: design.spacing.sm) {
            Image(systemName: "person.2")
                .foregroundColor(design.colors.textTertiary)
                .font(.system(size: 16))

            Text("Participant information unavailable")
                .font(design.fonts.callout)
                .foregroundColor(design.colors.textTertiary)
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(design.colors.backgroundSecondary)
        .cornerRadius(design.corners.medium)
    }

    private func attendeeRow(_ attendee: Attendee) -> some View {
        HStack(spacing: design.spacing.sm) {
            if let status = attendee.status {
                Image(systemName: status.iconName)
                    .foregroundColor(statusColor(for: status))
                    .font(.system(size: 12, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attendee.displayName)
                    .font(design.fonts.callout)
                    .foregroundColor(design.colors.textPrimary)
                    .lineLimit(1)

                if attendee.name != nil, attendee.name != attendee.email {
                    Text(attendee.email)
                        .font(design.fonts.caption1)
                        .foregroundColor(design.colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if attendee.isOrganizer {
                Text("Organizer")
                    .font(design.fonts.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(design.colors.accent)
                    .padding(.horizontal, design.spacing.sm)
                    .padding(.vertical, 2)
                    .background(design.colors.accent.opacity(0.1))
                    .cornerRadius(design.corners.small)
            } else if attendee.isOptional {
                Text("Optional")
                    .font(design.fonts.caption2)
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
                    .font(.system(size: 16, weight: .medium))

                Text("Join Meeting")
                    .font(design.fonts.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(design.colors.textPrimary)
            }

            VStack(spacing: design.spacing.sm) {
                ForEach(Array(event.links.enumerated()), id: \.offset) { _, link in
                    CustomButton(
                        "Join via \(event.provider?.displayName ?? "Link")",
                        icon: event.provider?.iconName ?? "link",
                        style: .primary
                    ) {
                        NSWorkspace.shared.open(link)
                    }
                }
            }
        }
        .padding(design.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(design.colors.backgroundSecondary)
        .cornerRadius(design.corners.medium)
    }

    // MARK: - Helper Methods

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func cleanDescription(_ description: String) -> String {
        // Remove HTML tags and clean up description
        let cleaned =
            description
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&[^;]+;", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "No description available" : cleaned
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

#Preview {
    let sampleEvent = Event(
        id: "sample",
        title: "Team Standup Meeting",
        startDate: Date(),
        endDate: Date().addingTimeInterval(1800),
        organizer: "manager@company.com",
        description:
        "Daily standup to discuss progress and blockers. Please come prepared with your updates.",
        location: "Conference Room A",
        attendees: [
            Attendee(
                name: "John Doe", email: "john@company.com", status: .accepted, isOrganizer: true,
                isSelf: false
            ),
            Attendee(name: "Jane Smith", email: "jane@company.com", status: .tentative, isSelf: false),
            Attendee(
                email: "contractor@external.com", status: .needsAction, isOptional: true, isSelf: false
            ),
        ],
        calendarId: "primary",
        links: [URL(string: "https://meet.google.com/abc-defg-hij")!]
    )

    MeetingDetailsView(event: sampleEvent)
        .customThemedEnvironment()
}
