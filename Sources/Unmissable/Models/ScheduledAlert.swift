import Foundation

struct ScheduledAlert: Identifiable, Equatable {
    let id = UUID()
    let event: Event
    let triggerDate: Date
    let alertType: AlertType

    enum AlertType: Equatable {
        case reminder(minutesBefore: Int)
        case snooze(until: Date)
        case meetingStart
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    /// Whether the trigger date has passed relative to the given reference time.
    /// Requires an explicit `Date` parameter to ensure callers reason about
    /// the result without wall-clock non-determinism.
    func isActive(at now: Date) -> Bool {
        now >= triggerDate
    }

    /// Seconds remaining until the trigger fires relative to the given reference time.
    func timeUntilTrigger(from now: Date) -> TimeInterval {
        triggerDate.timeIntervalSince(now)
    }
}
