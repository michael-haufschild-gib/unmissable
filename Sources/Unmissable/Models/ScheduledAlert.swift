import Foundation

struct ScheduledAlert: Identifiable, Sendable {
  let id = UUID()
  let event: Event
  let triggerDate: Date
  let alertType: AlertType

  enum AlertType: Sendable {
    case reminder(minutesBefore: Int)
    case snooze(until: Date)
    case meetingStart
  }

  var isActive: Bool {
    Date() >= triggerDate
  }

  var timeUntilTrigger: TimeInterval {
    triggerDate.timeIntervalSinceNow
  }
}
