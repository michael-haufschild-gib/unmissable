import Foundation

/// Centralized notification name constants to avoid typos and enable refactoring
extension Notification.Name {
  /// Posted when OAuth callback is received from the system
  static let oauthCallback = Notification.Name("com.unmissable.oauthCallback")

  /// Posted by macOS when Do Not Disturb preferences change
  static let dndPrefsChanged = Notification.Name("com.apple.notificationcenterui.dndprefs_changed")

  /// Posted by macOS when Focus state changes
  static let focusStateChanged = Notification.Name("com.apple.focus.state_changed")
}
