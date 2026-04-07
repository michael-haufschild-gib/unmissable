import Foundation
import Testing
@testable import Unmissable

@MainActor
struct EventDeduplicationTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let oneHour: TimeInterval = 3600

    // MARK: - No-op Cases

    @Test
    func noDuplicates_returnsAllEvents() {
        let events = [
            TestUtilities.createTestEvent(
                id: "e1",
                title: "Standup",
                startDate: baseDate,
                calendarId: "cal-google",
            ),
            TestUtilities.createTestEvent(
                id: "e2",
                title: "Retro",
                startDate: baseDate.addingTimeInterval(oneHour),
                calendarId: "cal-google",
            ),
        ]

        let result = CalendarService.deduplicateEvents(events)

        #expect(result.count == 2)
        #expect(result[0].id == "e1")
        #expect(result[1].id == "e2")
    }

    @Test
    func emptyArray_returnsEmpty() {
        let result = CalendarService.deduplicateEvents([])

        #expect(result.isEmpty)
    }

    // MARK: - Cross-Provider Deduplication

    @Test
    func crossProviderDuplicate_keepsOne() {
        let start = baseDate
        let end = baseDate.addingTimeInterval(oneHour)

        let events = [
            TestUtilities.createTestEvent(
                id: "google-123",
                title: "Team Sync",
                startDate: start,
                endDate: end,
                calendarId: "google-primary",
            ),
            TestUtilities.createTestEvent(
                id: "apple-abc",
                title: "Team Sync",
                startDate: start,
                endDate: end,
                calendarId: "apple-cal-id",
            ),
        ]

        let result = CalendarService.deduplicateEvents(events)

        #expect(result.count == 1)
        #expect(result[0].title == "Team Sync")
    }

    @Test
    func prefersEventWithMoreLinks() throws {
        let start = baseDate
        let end = baseDate.addingTimeInterval(oneHour)
        let meetLink = try #require(
            URL(string: "https://meet.google.com/abc-defg-hij"),
        )

        let googleEvent = TestUtilities.createTestEvent(
            id: "google-123",
            title: "Team Sync",
            startDate: start,
            endDate: end,
            calendarId: "google-primary",
            links: [meetLink],
        )
        let appleEvent = TestUtilities.createTestEvent(
            id: "apple-abc",
            title: "Team Sync",
            startDate: start,
            endDate: end,
            calendarId: "apple-cal-id",
        )

        let result = CalendarService.deduplicateEvents(
            [appleEvent, googleEvent],
        )

        #expect(result.count == 1)
        #expect(result[0].id == "google-123")
        #expect(result[0].links.count == 1)
    }

    @Test
    func tripleProvider_keepsOne() {
        let start = baseDate
        let end = baseDate.addingTimeInterval(oneHour)

        let events = [
            TestUtilities.createTestEvent(
                id: "e1",
                title: "All Hands",
                startDate: start,
                endDate: end,
                calendarId: "cal-1",
            ),
            TestUtilities.createTestEvent(
                id: "e2",
                title: "All Hands",
                startDate: start,
                endDate: end,
                calendarId: "cal-2",
            ),
            TestUtilities.createTestEvent(
                id: "e3",
                title: "All Hands",
                startDate: start,
                endDate: end,
                calendarId: "cal-3",
            ),
        ]

        let result = CalendarService.deduplicateEvents(events)

        #expect(result.count == 1)
    }

    // MARK: - Non-Duplicate Cases

    @Test
    func differentTitles_notDeduplicated() {
        let events = [
            TestUtilities.createTestEvent(
                id: "e1",
                title: "Standup",
                startDate: baseDate,
                calendarId: "cal-1",
            ),
            TestUtilities.createTestEvent(
                id: "e2",
                title: "Retro",
                startDate: baseDate,
                calendarId: "cal-2",
            ),
        ]

        let result = CalendarService.deduplicateEvents(events)

        #expect(result.count == 2)
    }

    @Test
    func differentStartTimes_notDeduplicated() {
        let events = [
            TestUtilities.createTestEvent(
                id: "e1",
                title: "Standup",
                startDate: baseDate,
                calendarId: "cal-1",
            ),
            TestUtilities.createTestEvent(
                id: "e2",
                title: "Standup",
                startDate: baseDate.addingTimeInterval(oneHour),
                calendarId: "cal-2",
            ),
        ]

        let result = CalendarService.deduplicateEvents(events)

        #expect(result.count == 2)
    }

    // MARK: - Edge Cases

    @Test
    func titleWithTrailingWhitespace_stillDeduplicated() {
        let start = baseDate
        let end = baseDate.addingTimeInterval(oneHour)

        let events = [
            TestUtilities.createTestEvent(
                id: "e1",
                title: "Team Sync",
                startDate: start,
                endDate: end,
                calendarId: "cal-1",
            ),
            TestUtilities.createTestEvent(
                id: "e2",
                title: "Team Sync ",
                startDate: start,
                endDate: end,
                calendarId: "cal-2",
            ),
        ]

        let result = CalendarService.deduplicateEvents(events)

        #expect(result.count == 1)
    }
}
