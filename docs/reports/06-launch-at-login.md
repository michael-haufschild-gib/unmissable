# Launch at Login

## Summary

Add automatic launch-at-login so Unmissable starts when the user logs into their Mac. A meeting reminder that doesn't survive a reboot is a meeting the user will miss. This is the #2 blocker from the market readiness assessment.

## Why This Matters

Every competitor (In Your Face, MeetingBar, Dato) launches at login by default. A user who reboots their Mac on Monday morning and forgets to manually open Unmissable will miss their first meeting. That's the exact scenario the app is designed to prevent. The irony of a "never miss meetings" app that itself gets missed after reboot would be a 1-star review.

## Current State

There is no launch-at-login integration in the codebase. No `SMAppService`, no `LaunchAtLogin` package, no login item configuration.

The app already runs as a menu bar accessory (`AppDelegate.swift:9` — `NSApp.setActivationPolicy(.accessory)`), which is the correct configuration for a login item.

## Implementation Plan

### Option A: SMAppService (recommended for App Store)

macOS 13+ provides `SMAppService` for registering login items. This is the Apple-sanctioned approach and works correctly with App Sandbox (required for App Store distribution).

#### 1. Add preference toggle

**File:** `Sources/Unmissable/Features/Preferences/PreferencesManager.swift`

Add a new preference:

```swift
@Published
private(set) var launchAtLogin: Bool = true  // Default ON
func setLaunchAtLogin(_ value: Bool) {
    launchAtLogin = value
    userDefaults.set(value, forKey: PrefKey.launchAtLogin)
    updateLoginItemRegistration(enabled: value)
}
```

Add `case launchAtLogin` to `PrefKey` enum.

#### 2. Register/unregister login item

**File:** `Sources/Unmissable/Features/Preferences/PreferencesManager.swift` or a new `LoginItemManager`

```swift
import ServiceManagement

private func updateLoginItemRegistration(enabled: Bool) {
    do {
        let service = SMAppService.mainApp
        if enabled {
            try service.register()
            logger.info("Registered as login item")
        } else {
            try service.unregister()
            logger.info("Unregistered login item")
        }
    } catch {
        logger.error("Failed to update login item: \(error.localizedDescription)")
    }
}
```

#### 3. Register on first launch

**File:** `Sources/Unmissable/App/AppDelegate.swift`

On `applicationDidFinishLaunching`, if this is the first launch (no `launchAtLogin` key in UserDefaults), register the login item and set the preference to `true`. This ensures the app auto-starts by default without requiring user action.

```swift
// In applicationDidFinishLaunching:
if !UserDefaults.standard.contains(key: "launchAtLogin") {
    // First launch — enable by default
    preferencesManager.setLaunchAtLogin(true)
}
```

#### 4. Add UI toggle in preferences

**File:** `Sources/Unmissable/Features/Preferences/PreferencesView.swift`

Add to the General tab, in a new "Startup" section:

```swift
HStack {
    VStack(alignment: .leading, spacing: design.spacing.xs) {
        Text("Launch at login")
            .font(design.fonts.callout)
            .foregroundColor(design.colors.textPrimary)
        Text("Start Unmissable automatically when you log in")
            .font(design.fonts.caption1)
            .foregroundColor(design.colors.textSecondary)
    }
    Spacer()
    CustomToggle(isOn: preferences.launchAtLoginBinding)
}
```

### Option B: LaunchAtLogin SPM package (for non-App Store)

If distributing outside the App Store, the [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) package by Sindre Sorhus wraps `SMAppService` with a SwiftUI `Toggle` and handles edge cases. However, for App Store builds, `SMAppService` directly is simpler and avoids an unnecessary dependency.

**Recommendation:** Use `SMAppService` directly. It's 10 lines of code and avoids a dependency for trivial functionality.

## Key Design Decisions

- **Default ON.** A meeting reminder should launch at login by default. Users who don't want this can toggle it off. This matches In Your Face and MeetingBar behavior.
- **`SMAppService.mainApp`** is the correct API for menu bar apps. It registers the current app binary as a login item. No helper app or LaunchAgent needed.
- **macOS 13+ only.** `SMAppService` requires macOS 13 (Ventura). The app already targets macOS 14 (Sonoma), so this is not a constraint.
- **No `ServiceManagement` entitlement needed** for `SMAppService.mainApp` — it works out of the box for the app's own binary.
- **State sync.** On launch, check `SMAppService.mainApp.status` to sync the preference toggle with the actual system state (the user might have changed it in System Settings > General > Login Items).

## Testing

- Unit test: `setLaunchAtLogin(true)` calls `SMAppService.mainApp.register()` (requires mocking or integration test)
- Unit test: preference persists to UserDefaults
- Manual test: toggle on → reboot → app starts automatically
- Manual test: toggle off → reboot → app does not start
- Manual test: check System Settings > Login Items shows/hides Unmissable

## Estimated Scope

Small. One new preference key, ~20 lines of `SMAppService` integration, one UI toggle. Estimated: 30 minutes including the preference UI.
