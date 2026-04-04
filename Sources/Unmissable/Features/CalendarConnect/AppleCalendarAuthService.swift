import EventKit
import Foundation
import Observation
import OSLog

/// Handles EventKit permission requests for Apple Calendar access.
/// No OAuth needed — uses the system permission dialog.
@Observable
final class AppleCalendarAuthService: CalendarAuthProviding {
    private let logger = Logger(category: "AppleCalendarAuth")
    @ObservationIgnored
    private let eventStore: EKEventStore

    private static let calendarDeniedMessage =
        "Calendar access denied. Grant access in " +
        "System Settings > Privacy & Security > Calendars."

    var isAuthenticated = false
    var userEmail: String?
    var authorizationError: String?

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        updateAuthStatus()
    }

    func startAuthorizationFlow() async throws {
        logger.info("Requesting EventKit calendar access")
        authorizationError = nil

        let granted = try await eventStore.requestFullAccessToEvents()

        if granted {
            logger.info("EventKit calendar access granted")
            isAuthenticated = true
            authorizationError = nil
        } else {
            logger.warning("EventKit calendar access denied")
            isAuthenticated = false
            authorizationError = Self.calendarDeniedMessage
        }
    }

    // Protocol conformance: CalendarAuthProviding requires async signature
    // swiftlint:disable:next async_without_await
    func validateAuthState() async {
        updateAuthStatus()
    }

    func signOut() {
        logger.info("Signing out of Apple Calendar")
        // EventKit permissions can't be revoked programmatically.
        // We just clear local state so the app treats it as disconnected.
        isAuthenticated = false
        userEmail = nil
        authorizationError = nil
    }

    private func updateAuthStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            isAuthenticated = true
            authorizationError = nil

        case .denied, .restricted:
            isAuthenticated = false
            authorizationError = Self.calendarDeniedMessage

        case .notDetermined, .writeOnly:
            isAuthenticated = false
            authorizationError = nil

        @unknown default:
            isAuthenticated = false
            authorizationError = nil
        }
        // EventKit doesn't expose user email
        userEmail = nil
    }
}
