# Smart Alert Suppression

## Summary

Suppress the full-screen overlay when the user already has the meeting's video app in the foreground. If Zoom is the active window and the meeting is a Zoom meeting, the user is clearly aware of (or already in) the meeting. Showing a blocking overlay at that point is disruptive rather than helpful.

## Why This Matters

The overlay is designed for the case where the user is deeply focused on something else and unaware a meeting is starting. If the user already has the meeting app open, the overlay goes from "helpful reminder" to "annoying interruption." This is the most common complaint about aggressive meeting reminders — they don't know when to back off.

## Current State

### Overlay trigger flow

`EventScheduler.swift` fires `overlayManager.showOverlay(for:fromSnooze:)` when an alert triggers. `OverlayManager.swift:57-109` runs through guards (duplicate check, Focus/DND mode, auto-dismiss for old meetings) before creating overlay windows. There is no check for the currently active application.

### Focus mode detection

`FocusModeManager.swift` already detects macOS Do Not Disturb status and exposes `shouldShowOverlay()`. The smart suppression logic should follow the same pattern — a method on a manager that `OverlayManager` consults before showing.

### Meeting link to app mapping

`Provider.swift` maps URLs to meeting providers (`.meet`, `.zoom`, `.teams`, `.webex`, `.generic`). `LinkParser.swift` detects the primary link for each event. The provider → app bundle ID mapping is the missing piece.

## Implementation Plan

### 1. Create a provider-to-bundle-ID mapping

**File:** `Sources/Unmissable/Models/Provider.swift`

Add a computed property for known bundle IDs:

```swift
var knownBundleIdentifiers: [String] {
    switch self {
    case .meet:
        // Google Meet runs in browsers, check Safari/Chrome/Arc/etc.
        // Also: meet.google.com PWA if installed
        []  // See design decision below
    case .zoom:
        ["us.zoom.xos"]
    case .teams:
        ["com.microsoft.teams", "com.microsoft.teams2"]
    case .webex:
        ["com.webex.meetingmanager", "com.cisco.webexmeetings"]
    case .generic:
        []
    }
}
```

### 2. Detect foreground application

**File:** New file `Sources/Unmissable/Core/ForegroundAppDetector.swift`

Use `NSWorkspace.shared.frontmostApplication` to check the active app's bundle identifier. This is a lightweight, synchronous call that doesn't require any permissions.

```swift
@MainActor
final class ForegroundAppDetector {
    func isMeetingAppInForeground(for provider: Provider) -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        let frontBundleID = frontApp.bundleIdentifier ?? ""
        return provider.knownBundleIdentifiers.contains(frontBundleID)
    }

    func isBrowserShowingMeetingURL(_ url: URL) -> Bool {
        // For browser-based meetings (Google Meet), check if a browser is frontmost.
        // We can't check the URL tab — that would require accessibility permissions.
        // Best effort: if a browser is frontmost, assume the user might be joining.
        // This is a heuristic, not a guarantee.
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        let browserBundleIDs: Set<String> = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "company.thebrowser.Browser",  // Arc
            "com.brave.Browser",
            "com.microsoft.edgemac",
        ]
        return browserBundleIDs.contains(frontApp.bundleIdentifier ?? "")
    }
}
```

### 3. Integrate into OverlayManager

**File:** `Sources/Unmissable/Features/Overlay/OverlayManager.swift`

Add the suppression check in `showOverlay(for:fromSnooze:)`, after the Focus mode check and before window creation:

```swift
// Check if meeting app is already in foreground
if let provider = event.provider,
   foregroundAppDetector.isMeetingAppInForeground(for: provider) {
    logger.info("SMART SUPPRESS: Meeting app already in foreground for \(event.id)")
    return
}
```

### 4. Add a preference toggle

**File:** `Sources/Unmissable/Features/Preferences/PreferencesManager.swift`

Add `smartSuppression: Bool` (default: `true`). Users who want the overlay regardless can disable it.

### 5. Handle the Google Meet problem

Google Meet runs in a browser tab, not a dedicated app. Options:

- **Option A (recommended):** If a browser is frontmost AND the event's provider is `.meet`, suppress the overlay. This is a heuristic — the user might have a browser open for other reasons. Accept the false-positive rate as the cost of being non-intrusive.
- **Option B:** Use Accessibility APIs to read the browser's active tab URL. Requires the user to grant accessibility permissions — too invasive for this feature.
- **Option C:** Don't suppress for browser-based meetings. Only suppress for native apps (Zoom, Teams, WebEx). Simple, no false positives, but misses the most common case.

Recommendation: **Option A** with the preference toggle. If users find it too aggressive, they disable it.

## Key Design Decisions

- **Suppression, not cancellation.** When suppressed, the alert is still "consumed" — it doesn't re-trigger. The assumption is: if the meeting app is open, the user knows about the meeting. If they want a re-reminder, they can rely on the snooze mechanism for a future meeting.
- **fromSnooze alerts are NOT suppressed.** If the user explicitly snoozed, they asked to be reminded. Show the overlay even if the meeting app is open.
- **Sound is also suppressed** when the overlay is suppressed. No point playing an alert sound if we've decided the user doesn't need interrupting.
- **Log suppression events** for health monitoring — if every alert is being suppressed, something might be wrong.

## Testing

- Unit test: `isMeetingAppInForeground` returns `true` when matching bundle ID is active (mock `NSWorkspace`)
- Unit test: `showOverlay` skips when smart suppression triggers, does not skip for `fromSnooze: true`
- Unit test: suppression respects the preference toggle
- Integration test: suppression is logged in health monitoring

## Estimated Scope

Small-to-medium. New file for detection, small changes to OverlayManager and PreferencesManager. The Google Meet browser heuristic is the only complex decision.
