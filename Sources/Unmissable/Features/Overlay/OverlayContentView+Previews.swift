import SwiftUI

// MARK: - Overlay Content Previews

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
