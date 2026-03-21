import AppKit
import Foundation

// MARK: - Protocol Definitions for Dependency Injection

/// Protocol for overlay scheduling and display functionality
@MainActor
protocol OverlayManaging: ObservableObject {
    var activeEvent: Event? { get }
    var isOverlayVisible: Bool { get }
    /// Computed time until meeting starts (negative if meeting has started)
    var timeUntilMeeting: TimeInterval { get }

    func showOverlay(for event: Event, fromSnooze: Bool)
    func hideOverlay()
    func snoozeOverlay(for minutes: Int)
    func setEventScheduler(_ scheduler: EventScheduler)
}

// MARK: - OverlayManaging Convenience Overloads

extension OverlayManaging {
    /// Show overlay with default fromSnooze = false, used in tests
    func showOverlayImmediately(for event: Event, fromSnooze: Bool = false) {
        showOverlay(for: event, fromSnooze: fromSnooze)
    }
}

/// Protocol for meeting details popup functionality
@MainActor
protocol MeetingDetailsPopupManaging: ObservableObject {
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

// MARK: - Calendar Provider Protocols

/// Protocol for calendar API data fetching, abstracting the provider (Google, Apple, etc.)
@MainActor
protocol CalendarAPIProviding: ObservableObject {
    var calendars: [CalendarInfo] { get }
    var events: [Event] { get }
    var lastError: String? { get }

    @discardableResult
    func fetchCalendars() async -> [CalendarInfo]
    @discardableResult
    func fetchEvents(for calendarIds: [String], from startDate: Date, to endDate: Date) async
        -> [Event]
}

/// Protocol for calendar authentication, abstracting the auth mechanism (OAuth, EventKit, etc.)
@MainActor
protocol CalendarAuthProviding: ObservableObject {
    var isAuthenticated: Bool { get }
    var userEmail: String? { get }
    var authorizationError: String? { get }

    func startAuthorizationFlow() async throws
    func validateAuthState() async
    func signOut()
}
