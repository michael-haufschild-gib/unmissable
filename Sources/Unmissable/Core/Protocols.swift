import AppKit
import Foundation

// MARK: - Protocol Definitions for Dependency Injection

/// Protocol for overlay scheduling and display functionality
protocol OverlayManaging: AnyObject {
    var activeEvent: Event? { get }
    var isOverlayVisible: Bool { get }
    /// Computed time until meeting starts (negative if meeting has started)
    var timeUntilMeeting: TimeInterval { get }

    func showOverlay(for event: Event, fromSnooze: Bool)
    func hideOverlay()
    func snoozeOverlay(for minutes: Int)
}

// MARK: - OverlayManaging Convenience Overloads

extension OverlayManaging {
    /// Show overlay with default fromSnooze = false, used in tests
    func showOverlayImmediately(for event: Event, fromSnooze: Bool = false) {
        showOverlay(for: event, fromSnooze: fromSnooze)
    }
}

/// Protocol for meeting details popup functionality
protocol MeetingDetailsPopupManaging: AnyObject {
    var isPopupVisible: Bool { get }

    func showPopup(for event: Event, relativeTo parentWindow: NSWindow?)
    func hidePopup()
}

// MARK: - MeetingDetailsPopupManaging Convenience Overloads

extension MeetingDetailsPopupManaging {
    func showPopup(for event: Event) {
        showPopup(for: event, relativeTo: nil)
    }
}

// MARK: - Notification Managing

/// Protocol for delivering macOS Notification Center alerts as a lighter
/// alternative to the full-screen overlay.
protocol NotificationManaging {
    /// Request user authorization for notifications. Returns true if granted.
    func requestPermission() async -> Bool

    /// Deliver a meeting notification for the given event.
    func sendMeetingNotification(for event: Event, primaryLink: URL?) async

    /// Register notification action categories (call once at app launch).
    func registerCategories()
}

// MARK: - Foreground App Detection

/// Detects the frontmost application to support smart alert suppression.
/// When the user already has a meeting app in the foreground, the overlay is unnecessary.
protocol ForegroundAppDetecting {
    /// Whether the native app for the given provider is the frontmost application.
    func isMeetingAppInForeground(for provider: Provider) -> Bool

    /// Whether any common web browser is the frontmost application.
    /// Used as a heuristic for browser-based meeting providers (e.g. Google Meet).
    func isBrowserInForeground() -> Bool
}

// MARK: - Calendar Provider Protocols

/// Per-calendar fetch results. Each requested calendar ID maps to either its events
/// or the error that prevented fetching. Enables callers to make correct per-calendar
/// decisions (clear cache on success-empty vs. preserve cache on failure).
typealias CalendarFetchResults = [String: Result<[Event], any Error>]

/// Protocol for calendar API data fetching, abstracting the provider (Google, Apple, etc.)
protocol CalendarAPIProviding {
    var calendars: [CalendarInfo] { get }
    var events: [Event] { get }
    var lastError: String? { get }

    @discardableResult
    func fetchCalendars() async -> [CalendarInfo]
    @discardableResult
    func fetchEvents(for calendarIds: [String], from startDate: Date, to endDate: Date) async
        -> CalendarFetchResults
}

/// Protocol for calendar authentication, abstracting the auth mechanism (OAuth, EventKit, etc.)
protocol CalendarAuthProviding {
    var isAuthenticated: Bool { get }
    var userEmail: String? { get }
    var authorizationError: String? { get }

    func startAuthorizationFlow() async throws
    func validateAuthState() async
    func signOut()
}
