# Onboarding Flow

## Summary

Build a 3-screen onboarding experience for first-time users: Welcome → Connect Calendar → You're All Set. Currently, a new user opens the app and sees the menu bar dropdown with "Connect Apple Calendar" / "Connect Google Calendar" buttons and no context. A paying customer needs to understand the value and complete setup within 60 seconds.

## Why This Matters

The App Store purchase flow is: see listing → buy ($4.99) → download → open → ???. If that last step is confusing or underwhelming, the customer requests a refund. Apple allows refunds within 14 days. The onboarding must:
1. Confirm the customer made a good purchase ("here's what this app does")
2. Get them connected to a calendar in under 60 seconds
3. Show them the value immediately (first meeting in their list, or a demo overlay)

## Current State

### First launch experience

When the app first launches:
- `AppDelegate.swift:9` sets the app as a menu bar accessory (no dock icon)
- `AppDelegate.swift:71-77` requests accessibility permissions (system dialog appears)
- `AppState.swift:81-96` checks initial state — if no calendar is connected, the menu bar shows `disconnectedContent` (`MenuBarView.swift:273-323`)
- The disconnected state shows two buttons: "Connect Apple Calendar" and "Connect Google Calendar" with no explanation

### What's missing

- No welcome screen explaining what the app does
- No visual preview of the overlay (the user hasn't seen the core feature yet)
- No guidance on which calendar to connect
- No "success" confirmation after connecting
- The accessibility permission dialog appears immediately with no context (user may deny it)

## Implementation Plan

### 1. Track first-launch state

**File:** `Sources/Unmissable/Features/Preferences/PreferencesManager.swift`

Add:
```swift
@Published
private(set) var hasCompletedOnboarding: Bool = false
func setHasCompletedOnboarding(_ value: Bool) {
    hasCompletedOnboarding = value
    userDefaults.set(value, forKey: PrefKey.hasCompletedOnboarding)
}
```

Add `case hasCompletedOnboarding` to `PrefKey` enum.

### 2. Create OnboardingView

**File:** New file `Sources/Unmissable/Features/Onboarding/OnboardingView.swift`

A 3-step flow presented in a standalone window (not the menu bar dropdown):

#### Screen 1: Welcome

```
[Calendar icon with clock badge — large, centered]

Welcome to Unmissable

Full-screen reminders you can't ignore.
Never miss a meeting again.

[Continue →]
```

Key elements:
- App icon/branding at top
- One-sentence value proposition
- Brief feature highlights (3 bullet points max):
  - "Full-screen overlay before every meeting"
  - "One-click join for Zoom, Meet, Teams, and more"
  - "Works with Google Calendar and Apple Calendar"

#### Screen 2: Connect Calendar

```
[Calendar connection illustration]

Connect Your Calendar

Choose how you'd like to sync your meetings.

[Apple Calendar icon] Connect Apple Calendar
  Uses calendars from iCloud, Outlook, Exchange, and more.
  Recommended for most users.

[Google Calendar icon] Connect Google Calendar
  Direct connection to your Google account.
  Best for Google Workspace users.

[Skip for now — set up later in Preferences]
```

Key elements:
- Brief explanation of what each option covers
- "Recommended" badge on Apple Calendar (covers the most providers via one connection)
- Skip option (don't force connection — the user might want to explore first)
- After successful connection, auto-advance to screen 3

#### Screen 3: You're All Set

```
[Checkmark animation]

You're All Set!

Unmissable is running in your menu bar.
Your next meeting will trigger a full-screen reminder.

[Show me how it looks]   [Done]
```

Key elements:
- Confirmation that the app is running
- "Show me how it looks" button triggers a demo overlay with a fake event ("Demo Meeting" starting in 2 minutes) so the user sees the core feature immediately
- "Done" closes the onboarding window
- Mention where to find the app (menu bar icon) and how to access Preferences

### 3. Create OnboardingWindowManager

**File:** New file `Sources/Unmissable/Features/Onboarding/OnboardingWindowManager.swift`

Similar pattern to `PreferencesWindowManager` — manages a standalone `NSWindow` that hosts the onboarding SwiftUI view.

```swift
@MainActor
final class OnboardingWindowManager {
    private var window: NSWindow?

    func showOnboarding(appState: AppState) {
        let onboardingView = OnboardingView(appState: appState)
            .environmentObject(appState.preferences)
            .customThemedEnvironment(themeManager: appState.themeManager)

        let hostingView = NSHostingView(rootView: onboardingView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = hostingView
        window.title = "Welcome to Unmissable"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}
```

### 4. Trigger onboarding on first launch

**File:** `Sources/Unmissable/App/AppState.swift`

In `checkInitialState()`, after checking database status:

```swift
if !preferences.hasCompletedOnboarding {
    onboardingWindowManager.showOnboarding(appState: self)
}
```

### 5. Demo overlay

**File:** `Sources/Unmissable/Features/Onboarding/OnboardingView.swift`

The "Show me how it looks" button creates a fake event and shows the overlay:

```swift
let demoEvent = Event(
    id: "onboarding-demo",
    title: "Team Standup",
    startDate: Date().addingTimeInterval(120),
    endDate: Date().addingTimeInterval(1920),
    organizer: "you@company.com",
    calendarId: "demo",
    links: [URL(string: "https://meet.google.com/abc-defg-hij")!]
)
overlayManager.showOverlay(for: demoEvent, fromSnooze: false)
```

The overlay dismisses normally (ESC or Dismiss button). After dismissal, the user has experienced the core feature.

### 6. Defer accessibility permission prompt

**File:** `Sources/Unmissable/App/AppDelegate.swift`

Currently, `requestPermissions()` is called in `applicationDidFinishLaunching`. Move this to after onboarding completes, or at least to screen 3 with a brief explanation:

> "Unmissable uses keyboard shortcuts to dismiss alerts and join meetings. macOS needs your permission to enable this."
> [Enable Shortcuts] — triggers the accessibility permission dialog

This gives context before the system dialog appears, increasing the approval rate.

## Key Design Decisions

- **Standalone window, not menu bar.** The menu bar dropdown is too small for onboarding. A centered window (500x600) gives room for illustrations, text, and buttons. Matches how In Your Face and Dato handle first-run.
- **Apple Calendar recommended by default.** Apple Calendar acts as a bridge to iCloud, Outlook, Exchange, and Google Calendar (if the user has added their Google account to macOS). For most users, this is the simplest path. Google direct OAuth is offered as an alternative for Google Workspace users who want direct API access.
- **Skip option available.** Don't force calendar connection. Some users want to explore the app first. The disconnected state in the menu bar still shows the connection buttons.
- **Demo overlay is optional.** The "Show me how it looks" button is a delighter, not a gate. Users who click "Done" skip it and discover the overlay naturally at their next meeting.
- **Onboarding only shows once.** Guarded by `hasCompletedOnboarding` in UserDefaults. No way to re-trigger it (user can find everything in Preferences).

## Testing

- Unit test: `hasCompletedOnboarding` defaults to `false`, set to `true` after completion
- Unit test: onboarding window is shown when `hasCompletedOnboarding` is `false`
- Unit test: onboarding window is NOT shown when `hasCompletedOnboarding` is `true`
- Unit test: calendar connection from onboarding screen advances to screen 3
- Unit test: demo overlay creates a valid event and triggers overlay
- Manual test: full first-launch flow on a clean install

## Estimated Scope

Medium. New OnboardingView (3 screens), OnboardingWindowManager, one preference key, demo overlay logic. Estimated: 3-4 hours including visual polish. The demo overlay reuses existing OverlayManager infrastructure.
