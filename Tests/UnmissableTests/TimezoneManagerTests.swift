@testable import Unmissable
import XCTest

final class TimezoneManagerTests: XCTestCase {
    func testFormatEventTimeIncludeTimezone_usesEventDateTimezoneAbbreviation() throws {
        let timezoneID = "America/Los_Angeles"
        let timezone = try XCTUnwrap(TimeZone(identifier: timezoneID))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let winterDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 10, minute: 0))
        )
        let summerDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 10, minute: 0))
        )

        let winterEvent = Event(
            id: "winter-event",
            title: "Winter Sync",
            startDate: winterDate,
            endDate: winterDate.addingTimeInterval(3600),
            calendarId: "primary",
            timezone: timezoneID
        )
        let summerEvent = Event(
            id: "summer-event",
            title: "Summer Sync",
            startDate: summerDate,
            endDate: summerDate.addingTimeInterval(3600),
            calendarId: "primary",
            timezone: timezoneID
        )

        let winterAbbreviation = try XCTUnwrap(timezone.abbreviation(for: winterDate))
        let summerAbbreviation = try XCTUnwrap(timezone.abbreviation(for: summerDate))

        XCTAssertNotEqual(winterAbbreviation, summerAbbreviation)

        let manager = TimezoneManager.shared
        let winterText = manager.formatEventTime(winterEvent, includeTimezone: true)
        let summerText = manager.formatEventTime(summerEvent, includeTimezone: true)

        XCTAssertTrue(winterText.contains(winterAbbreviation))
        XCTAssertTrue(summerText.contains(summerAbbreviation))
    }
}
