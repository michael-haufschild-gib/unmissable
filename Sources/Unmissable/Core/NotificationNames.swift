import Foundation

/// Centralized notification name constants to avoid typos and enable refactoring
extension Notification.Name {
    /// Posted when OAuth callback is received from the system
    static let oauthCallback = Notification.Name("com.unmissable.oauthCallback")

    /// Posted when the app is reopened to show the preferences window
    static let showPreferences = Notification.Name("com.unmissable.showPreferences")
}
