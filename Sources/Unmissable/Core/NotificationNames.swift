import Foundation

/// Centralized notification name constants to avoid typos and enable refactoring
extension Notification.Name {
    /// Posted when OAuth callback is received from the system
    static let oauthCallback = Notification.Name("com.unmissable.oauthCallback")

    /// Posted when the app is reopened to show the preferences window
    static let showPreferences = Notification.Name("com.unmissable.showPreferences")

    /// Posted by macOS when Do Not Disturb preferences change.
    ///
    /// **Fragility:** This is an undocumented Apple private notification.
    /// It may stop firing in future macOS versions. `FocusModeManager` handles this
    /// gracefully by defaulting to "DND off" (overlays always shown) when detection fails.
    static let dndPrefsChanged = Notification.Name("com.apple.notificationcenterui.dndprefs_changed")

    /// Posted by macOS when Focus state changes.
    ///
    /// **Fragility:** This is an undocumented Apple private notification.
    /// See `dndPrefsChanged` for the degradation strategy.
    static let focusStateChanged = Notification.Name("com.apple.focus.state_changed")
}
