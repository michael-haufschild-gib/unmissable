# Notification Center Fallback

## Summary

Offer standard macOS Notification Center notifications as a lighter alternative to the full-screen overlay. Users could choose per-calendar or per-event whether to get the blocking overlay or a standard notification. This creates a spectrum of urgency: notification (low) → overlay (high).

## Why This Matters

The full-screen overlay is Unmissable's core differentiator — but it's also polarizing. Some meetings (optional all-hands, FYI syncs) don't warrant blocking the entire screen. Users who can't fine-tune the urgency level will either:
1. Turn off alerts for low-priority calendars entirely (missing some meetings they should attend)
2. Get fatigued by overlays for every meeting (and start ignoring/dismissing reflexively)

A notification fallback gives users a middle ground: "Alert me, but don't block me."

## Current State

### Alert system

`EventScheduler.swift` triggers alerts by calling `overlayManager.showOverlay(for:fromSnooze:)`. There is no alternative alert path. The scheduler doesn't distinguish between "important" and "less important" alerts.

### Preferences

`PreferencesManager.swift` has no per-calendar alert mode preference. Alert timing is global (with length-based override). The `CalendarInfo` model has `isSelected: Bool` but no alert mode field.

### macOS notification APIs

macOS provides `UNUserNotificationCenter` for standard notifications. Key capabilities:
- Rich notifications with title, body, and actions (e.g., "Join" button)
- Notification sounds
- Notification grouping
- Respects system DND/Focus mode natively
- Requires requesting notification permission on first use

## Implementation Plan

### 1. Define alert mode enum

**File:** New addition to `Sources/Unmissable/Models/CalendarInfo.swift` or a shared types file

```swift
enum AlertMode: String, Codable, CaseIterable {
    case overlay      // Full-screen blocking overlay (current behavior)
    case notification // Standard macOS notification
    case none         // No alert (just show in menu bar)

    var displayName: String {
        switch self {
        case .overlay: "Full-Screen Overlay"
        case .notification: "Notification"
        case .none: "None"
        }
    }
}
```

### 2. Add alert mode to CalendarInfo

**File:** `Sources/Unmissable/Models/CalendarInfo.swift`

Add `alertMode: AlertMode` field (default: `.overlay` to preserve existing behavior).

**File:** `Sources/Unmissable/Core/DatabaseManager.swift`

Add a `v6` (or `v7` if per-event override takes `v6`) migration to add `alertMode TEXT NOT NULL DEFAULT 'overlay'` to the calendars table.

**File:** `Sources/Unmissable/Core/DatabaseModels.swift`

Add encoding/decoding for the new column in the `CalendarInfo` GRDB extension.

### 3. Create NotificationManager

**File:** New file `Sources/Unmissable/Core/NotificationManager.swift`

```swift
import UserNotifications

@MainActor
final class NotificationManager {
    private let linkParser: LinkParser

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func sendMeetingNotification(for event: Event) async {
        let content = UNMutableNotificationContent()
        content.title = "Upcoming Meeting"
        content.body = "\(event.title) — \(event.startDate, style: .time)"
        content.sound = .default

        // Add "Join" action if meeting link exists
        if linkParser.isOnlineMeeting(event) {
            content.categoryIdentifier = "MEETING_WITH_LINK"
        }

        let request = UNNotificationRequest(
            identifier: "meeting-\(event.id)",
            content: content,
            trigger: nil  // Deliver immediately (scheduler handles timing)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Log error, fall back silently
        }
    }

    func registerCategories() {
        let joinAction = UNNotificationAction(
            identifier: "JOIN_MEETING",
            title: "Join",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "MEETING_WITH_LINK",
            actions: [joinAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
```

### 4. Modify EventScheduler to route alerts

**File:** `Sources/Unmissable/Core/EventScheduler.swift`

When handling a triggered alert, look up the event's calendar to determine alert mode:

```swift
private func handleTriggeredAlert(_ alert: ScheduledAlert, overlayManager: any OverlayManaging) {
    let alertMode = resolveAlertMode(for: alert.event)

    switch (alert.alertType, alertMode) {
    case (.reminder, .overlay):
        overlayManager.showOverlay(for: alert.event, fromSnooze: false)
    case (.reminder, .notification):
        Task { await notificationManager.sendMeetingNotification(for: alert.event) }
    case (.reminder, .none):
        break  // No alert, event just appears in menu bar
    case (.snooze, _):
        // Snoozed alerts always use overlay (user explicitly asked for reminder)
        overlayManager.showOverlay(for: alert.event, fromSnooze: true)
    case (.meetingStart, _):
        // Auto-join logic unchanged
        if preferencesManager.autoJoinEnabled, let url = linkParser.primaryLink(for: alert.event) {
            NSWorkspace.shared.open(url)
        }
    }
}
```

### 5. Add per-calendar alert mode UI

**File:** `Sources/Unmissable/Features/Preferences/CalendarPreferencesView.swift`

Add an alert mode picker to each calendar row in the calendar selection section. Show a segmented control or picker with the three options (Overlay / Notification / None) next to each calendar's toggle.

### 6. Handle notification actions

**File:** `Sources/Unmissable/App/AppDelegate.swift` (or NotificationManager)

Implement `UNUserNotificationCenterDelegate` to handle the "Join" action:

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
) async {
    if response.actionIdentifier == "JOIN_MEETING" {
        let eventId = response.notification.request.identifier
            .replacingOccurrences(of: "meeting-", with: "")
        // Look up event, open primary link
    }
}
```

### 7. Request notification permission at appropriate time

Not during app launch (annoying). Instead:
- When the user first sets a calendar to "Notification" mode in preferences
- Or during onboarding flow (if/when onboarding is added)

## Key Design Decisions

- **Per-calendar, not per-event.** Adding alert mode to CalendarInfo is simpler than per-event and matches how users think ("my work calendar is high-priority, my social calendar is low-priority"). Per-event override (feature #1) can further refine this.
- **Default is overlay** to preserve existing behavior for all current users.
- **Snooze always uses overlay** regardless of calendar alert mode. If the user snoozed, they want a reminder they can't miss.
- **No badge count.** Meeting reminders are ephemeral — badge counts would accumulate and become noise.
- **Sandboxing compatibility.** `UNUserNotificationCenter` works correctly in sandboxed App Store apps. No entitlement needed beyond the standard notification permission prompt.

## Testing

- Unit test: `resolveAlertMode` returns correct mode per calendar
- Unit test: notification alerts do not trigger overlay, overlay alerts do not trigger notification
- Unit test: snooze always uses overlay regardless of calendar mode
- Integration test: notification delivered with correct title/body
- Integration test: "Join" action from notification opens correct URL

## Estimated Scope

Medium. New NotificationManager file, CalendarInfo model change, database migration, EventScheduler routing change, preferences UI update. The notification action handling adds some complexity.
