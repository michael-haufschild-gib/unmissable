import Foundation

/// Event grouping structure for date-based organization in the menu bar.
@MainActor
struct EventGroup: Identifiable {
    let title: String
    let events: [Event]

    var id: String {
        title
    }
}

/// Pure-logic utility for filtering and grouping events by date.
/// Extracted from MenuBarView to keep the view under the 500-line limit
/// and make the grouping logic independently testable.
@MainActor
enum EventGrouping {
    /// Returns the next weekday date if `tomorrow` falls on a weekend, otherwise nil.
    static func nextWeekday(after tomorrow: Date, calendar: Calendar) -> Date? {
        guard calendar.isDateInWeekend(tomorrow) else { return nil }
        var candidate = tomorrow
        while calendar.isDateInWeekend(candidate) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else {
                return nil
            }
            candidate = next
        }
        return candidate
    }

    /// Filters events to today only.
    static func todayEvents(
        from events: [Event],
        includeAllDay: Bool,
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> [Event] {
        let dateFiltered = events.filter { event in
            calendar.isDate(event.startDate, inSameDayAs: now)
        }
        return filterAllDay(dateFiltered, include: includeAllDay)
    }

    /// Filters events to today, tomorrow, and the next workday (if tomorrow is a weekend).
    static func upcomingEvents(
        from events: [Event],
        includeAllDay: Bool,
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> [Event] {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            return todayEvents(from: events, includeAllDay: includeAllDay, calendar: calendar, now: now)
        }
        let monday = nextWeekday(after: tomorrow, calendar: calendar)

        let dateFiltered = events.filter { event in
            calendar.isDate(event.startDate, inSameDayAs: now)
                || calendar.isDate(event.startDate, inSameDayAs: tomorrow)
                || (monday.map { calendar.isDate(event.startDate, inSameDayAs: $0) } ?? false)
        }
        return filterAllDay(dateFiltered, include: includeAllDay)
    }

    /// Cached weekday formatter — DateFormatter is expensive to construct.
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// Groups events by date into labeled sections (Started, Today, Tomorrow, weekday name).
    static func groupByDate(
        _ events: [Event],
        startedEvents: [Event] = [],
        includeAllDay: Bool,
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> [EventGroup] {
        var groups: [EventGroup] = []

        let startedFiltered = filterAllDay(startedEvents, include: includeAllDay)
        if !startedFiltered.isEmpty {
            groups.append(EventGroup(title: "Started", events: startedFiltered))
        }

        let todayEvents = filterAllDay(
            events.filter { calendar.isDate($0.startDate, inSameDayAs: now) },
            include: includeAllDay,
        )

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            if !todayEvents.isEmpty {
                groups.append(EventGroup(title: "Today", events: todayEvents))
            }
            return groups
        }

        let tomorrowEvents = filterAllDay(
            events.filter { calendar.isDate($0.startDate, inSameDayAs: tomorrow) },
            include: includeAllDay,
        )

        var nextWorkdayEvents: [Event] = []
        var nextWorkdayTitle = ""
        if let nextWorkday = nextWeekday(after: tomorrow, calendar: calendar) {
            nextWorkdayEvents = filterAllDay(
                events.filter { calendar.isDate($0.startDate, inSameDayAs: nextWorkday) },
                include: includeAllDay,
            )
            nextWorkdayTitle = weekdayFormatter.string(from: nextWorkday)
        }

        if !todayEvents.isEmpty {
            groups.append(EventGroup(title: "Today", events: todayEvents))
        }

        if !tomorrowEvents.isEmpty {
            groups.append(EventGroup(title: "Tomorrow", events: tomorrowEvents))
        }

        if !nextWorkdayEvents.isEmpty {
            groups.append(EventGroup(title: nextWorkdayTitle, events: nextWorkdayEvents))
        }

        return groups
    }

    // MARK: - Private

    private static func filterAllDay(_ events: [Event], include: Bool) -> [Event] {
        if include { return events }
        return events.filter { !$0.isAllDay }
    }
}
