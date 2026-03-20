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

    func showOverlay(for event: Event, minutesBeforeMeeting: Int, fromSnooze: Bool)
    func hideOverlay()
    func snoozeOverlay(for minutes: Int)
    func setEventScheduler(_ scheduler: EventScheduler)
}

// MARK: - OverlayManaging Convenience Overloads

extension OverlayManaging {
    /// Show overlay with default minutesBefore (5) and optional fromSnooze
    func showOverlay(for event: Event, fromSnooze: Bool = false) {
        showOverlay(for: event, minutesBeforeMeeting: 5, fromSnooze: fromSnooze)
    }

    /// Show overlay immediately (minutesBefore = 0), used in tests
    func showOverlayImmediately(for event: Event, fromSnooze: Bool = false) {
        showOverlay(for: event, minutesBeforeMeeting: 0, fromSnooze: fromSnooze)
    }
}

/// Protocol for event scheduling functionality
@MainActor
protocol EventScheduling: ObservableObject {
    func startScheduling(events: [Event], overlayManager: any OverlayManaging)
    func stopScheduling()
    func scheduleSnooze(for event: Event, minutes: Int)
}

/// Protocol for sound management
protocol SoundManaging {
    func playAlertSound()
}

/// Protocol for focus mode detection
@MainActor
protocol FocusModeManaging {
    func shouldShowOverlay() -> Bool
    func shouldPlaySound() -> Bool
}

/// Protocol for preferences management
@MainActor
protocol PreferencesManaging: ObservableObject {
    var overlayShowMinutesBefore: Int { get set }
    var soundEnabled: Bool { get set }
    var overlayOpacity: Double { get set }
    var appearanceTheme: AppTheme { get set }
    var showOnAllDisplays: Bool { get set }

    func alertMinutes(for event: Event) -> Int
}

/// Protocol for overlay rendering with error handling
@MainActor
protocol OverlayRendering: ObservableObject {
    var isRenderingOverlay: Bool { get }
    var lastRenderError: String? { get }

    func cleanup()
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
