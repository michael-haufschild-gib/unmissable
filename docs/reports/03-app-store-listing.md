# App Store Value Proposition and Listing

## Summary

Prepare the Mac App Store listing (screenshots, description, keywords, category) and the technical requirements for App Store distribution (receipt validation, entitlements, code signing, notarization). The value proposition: "$4.99 once vs $20/year for In Your Face, with multi-display support and Focus mode awareness."

## Why This Matters

This is the #1 blocker from the market readiness assessment. Without App Store distribution, the product cannot reach the target market. The App Store listing is also the first thing a potential customer sees — it determines whether they click "Buy" or move on. Every competitor (In Your Face, MeetingBar, Dato) is on the App Store.

## Current State

### Build system

`Package.swift` defines the app as an `.executableTarget` using SPM. Sparkle is included for auto-updates (not applicable for App Store builds — Apple handles updates). There is no Xcode project file (`.xcodeproj` or `.xcworkspace`), no entitlements file, no `Info.plist` for App Store metadata.

### App identity

The app runs as a menu bar app (`NSApp.setActivationPolicy(.accessory)` in `AppDelegate.swift:9`). It uses a custom URL scheme for OAuth callbacks (`GoogleCalendarConfig.redirectScheme`). The bundle identifier is not explicitly set in the SPM config.

### Signing and sandboxing

No code signing configuration visible. The app currently uses unsandboxed file access for:
- Focus/DND detection (`FocusModeManager.swift` reads `~/Library/DoNotDisturb/DB/Assertions.json`)
- Database storage in Application Support (`DatabaseManager.swift`)
- OAuth callback via custom URL scheme

App Store apps must be sandboxed. The DND file access will need an alternative approach (or graceful degradation — the code already handles sandboxed environments at `FocusModeManager.swift:117`).

## Implementation Plan

### Phase A: Technical Requirements

#### 1. Create Xcode project wrapper

SPM packages can be opened directly in Xcode, but App Store distribution requires an Xcode project with proper build settings. Either:
- **Option A:** Generate an `.xcodeproj` with `swift package generate-xcodeproj` (deprecated but functional)
- **Option B (recommended):** Create a minimal `.xcodeproj` that wraps the SPM package, setting bundle ID, signing team, entitlements, and Info.plist

#### 2. App Sandbox entitlements

Create `Unmissable.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>  <!-- For calendar API sync -->
    <key>com.apple.security.personal-information.calendars</key>
    <true/>  <!-- For Apple Calendar/EventKit access -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <false/>
</dict>
</plist>
```

Note: The database in Application Support works under sandboxing (macOS provides a container). OAuth custom URL scheme works under sandboxing. Global keyboard shortcuts via Magnet require accessibility permissions — the user is already prompted for this (`AppDelegate.swift:73`).

#### 3. Remove Sparkle dependency for App Store build

Sparkle is not allowed in App Store builds (Apple manages updates). Use a build configuration or conditional compilation:

```swift
#if !APPSTORE
import Sparkle
#endif
```

Or maintain two targets — one for direct distribution (with Sparkle) and one for App Store (without).

#### 4. App Store receipt validation

Add receipt validation to prevent piracy and ensure the app only runs when purchased through the App Store. Use Apple's `AppTransaction` API (available since macOS 13):

```swift
import StoreKit

func validateReceipt() async -> Bool {
    do {
        let result = try await AppTransaction.shared
        switch result {
        case .verified:
            return true
        case .unverified:
            return false
        }
    } catch {
        // Handle gracefully — allow the app to run if validation fails
        // (Apple recommends not being too aggressive)
        return true
    }
}
```

#### 5. Set bundle identifier and version

Choose a bundle ID (e.g., `com.unmissable.app` or your developer team prefix). Set `CFBundleShortVersionString` (e.g., `1.0.0`) and `CFBundleVersion` (e.g., `1`).

### Phase B: App Store Listing Content

#### 6. App name and subtitle

- **Name:** Unmissable
- **Subtitle:** Full-Screen Meeting Reminders (30 chars max)

#### 7. Description

Draft (4000 chars max):

> Never miss a meeting again. Unmissable shows a full-screen overlay with a live countdown timer before every meeting — impossible to ignore, even in deep focus.
>
> ONE-TIME PURCHASE. No subscription. Pay once, use forever.
>
> WHAT MAKES UNMISSABLE DIFFERENT:
> - Full-screen blocking overlay with countdown timer
> - Multi-display support — alerts on ALL your screens
> - Focus/Do Not Disturb mode awareness — configurable override
> - Smart alert timing based on meeting length
> - One-click join for Zoom, Google Meet, Teams, WebEx, and more
>
> WORKS WITH YOUR CALENDARS:
> Connect Google Calendar or Apple Calendar (which syncs with Outlook, Exchange, iCloud, and more). Select which calendars to monitor.
>
> CUSTOMIZABLE:
> - Alert timing: 1 to 15 minutes before meetings
> - Length-based timing: different alerts for short, medium, and long meetings
> - Overlay appearance: opacity, font size, minimal mode
> - Light, dark, or system theme
> - Snooze: 1, 5, 10, or 15 minutes
> - Global keyboard shortcuts
>
> PRIVACY FIRST:
> All data stays on your Mac. No analytics, no telemetry, no cloud accounts. Your calendar data is cached locally and never leaves your device.
>
> Built natively in Swift for macOS. Minimal resource usage. Runs quietly in your menu bar.

#### 8. Keywords (100 chars max)

`meeting,reminder,calendar,zoom,teams,overlay,timer,focus,ADHD,schedule`

#### 9. Category

Primary: Productivity
Secondary: Business

#### 10. Screenshots

Required: at least 1 screenshot. Recommended: 5-10 showing key flows.

Screenshot plan:
1. Menu bar with upcoming meetings list
2. Full-screen overlay with countdown (meeting approaching)
3. Full-screen overlay with "Join Meeting" button
4. Preferences > General (alert timing)
5. Preferences > Calendars (Google + Apple connected)
6. Preferences > Appearance (theme + menu bar modes)
7. Meeting details popup with attendees
8. Multi-display overlay (if possible to capture)

Screenshots must be at specific resolutions per Apple's guidelines. Use Xcode's simulator or a real Mac.

#### 11. App preview video (optional but recommended)

30-second video showing: launch → menu bar → meeting approaching → overlay appears → one-click join. This sells the core value proposition in under 30 seconds.

### Phase C: Pricing and Availability

#### 12. Set price tier

$4.99 = Apple's Tier 5. Apple takes 30% (15% after first year in the Small Business Program if revenue < $1M). Net revenue: $3.49/sale (or $4.24 with Small Business Program).

#### 13. Enroll in Apple Small Business Program

If eligible (< $1M revenue), enroll to reduce commission from 30% to 15%.

## Key Design Decisions

- **Sandboxing and DND detection:** The Focus/DND detection code already gracefully degrades in sandboxed environments (`FocusModeManager.swift:117` — returns `false` meaning "DND off", so overlays always show). This is acceptable behavior for App Store builds. Document this limitation.
- **Two distribution channels:** Consider maintaining both App Store (sandboxed, no Sparkle) and direct download (unsandboxed, with Sparkle, full DND detection). Many Mac apps do this (e.g., Dato has both).
- **OAuth and sandboxing:** Google OAuth with custom URL scheme should work in sandboxed apps. The callback URL handler is already in `AppDelegate.swift`. Test this thoroughly.
- **Magnet (global shortcuts) and sandboxing:** Global keyboard shortcuts require accessibility permissions regardless of sandboxing. The user prompt already exists. This should work.

## Testing

- Build and run in sandboxed mode — verify calendar sync, OAuth flow, overlay display, keyboard shortcuts all work
- Test receipt validation in TestFlight
- Test DND graceful degradation in sandbox
- Verify database creation in sandbox container path
- Screenshot capture at required resolutions

## Estimated Scope

Large. This is a multi-day effort spanning Xcode project setup, entitlements, conditional compilation for Sparkle, receipt validation, screenshot creation, and App Store metadata. But it is the single highest-impact item for market readiness.
