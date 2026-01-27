import Foundation
import OSLog

final class TimezoneManager: Sendable {
  private let logger = Logger(subsystem: "com.unmissable.app", category: "TimezoneManager")

  static let shared = TimezoneManager()

  private init() {}

  // MARK: - Event Timezone Handling

  /// Preserve absolute timestamps; only presentation (formatting) should apply time zones.
  func localizedEvent(_ event: Event) -> Event {
    return Event(
      id: event.id,
      title: event.title,
      startDate: event.startDate,
      endDate: event.endDate,
      organizer: event.organizer,
      description: event.description,
      location: event.location,
      attendees: event.attendees,
      attachments: event.attachments,
      isAllDay: event.isAllDay,
      calendarId: event.calendarId,
      timezone: event.timezone,  // keep original tz metadata
      links: event.links,
      provider: event.provider,
      snoozeUntil: event.snoozeUntil,
      autoJoinEnabled: event.autoJoinEnabled,
      createdAt: event.createdAt,
      updatedAt: event.updatedAt
    )
  }

  // MARK: - Alert Timing

  func calculateAlertTime(for event: Event, minutesBefore: Int) -> Date {
    return event.startDate.addingTimeInterval(-TimeInterval(minutesBefore * 60))
  }

  func timeUntilEvent(_ event: Event) -> TimeInterval {
    return event.startDate.timeIntervalSinceNow
  }

  func isEventStartingSoon(_ event: Event, within minutes: Int) -> Bool {
    let timeUntil = timeUntilEvent(event)
    let threshold = TimeInterval(minutes * 60)
    return timeUntil > 0 && timeUntil <= threshold
  }

  // MARK: - Timezone Information

  func getTimezoneDisplayName(_ timezone: String) -> String {
    guard let tz = TimeZone(identifier: timezone) else { return timezone }
    return tz.localizedName(for: .shortStandard, locale: .current) ?? timezone
  }

  func getCurrentTimezoneOffset() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "Z"
    return formatter.string(from: Date())
  }

  // MARK: - Date Formatting

  func formatEventTime(_ event: Event, includeTimezone: Bool = false) -> String {
    let formatter = DateFormatter()

    if event.isAllDay {
      formatter.dateStyle = .medium
      formatter.timeStyle = .none
      return formatter.string(from: event.startDate)
    } else {
      formatter.dateStyle = .none
      formatter.timeStyle = .short

      if includeTimezone {
        formatter.timeZone = TimeZone(identifier: event.timezone)
        let timeString = formatter.string(from: event.startDate)
        let tzName = getTimezoneDisplayName(event.timezone)
        return "\(timeString) \(tzName)"
      } else {
        formatter.timeZone = .current
        return formatter.string(from: event.startDate)
      }
    }
  }

  func formatRelativeTime(to date: Date) -> String {
    let now = Date()
    let interval = date.timeIntervalSince(now)

    if interval < 0 { return "Past" }

    let minutes = Int(interval / 60)
    let hours = minutes / 60
    let days = hours / 24

    if minutes < 1 {
      return "Now"
    } else if minutes < 60 {
      return "\(minutes)m"
    } else if hours < 24 {
      return "\(hours)h"
    } else {
      return "\(days)d"
    }
  }

  // MARK: - System Timezone Changes
}

// Intentionally no custom timezone change notifications; rely on NSSystemTimeZoneDidChange.
