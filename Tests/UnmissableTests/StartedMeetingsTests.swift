@testable import Unmissable
import XCTest

@MainActor
final class StartedMeetingsTests: DatabaseTestCase {
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        try await super.setUp() // This calls TestDataCleanup.shared.cleanupAllTestData()

        // Use the shared instance for testing
        databaseManager = DatabaseManager.shared
    }

    override func tearDown() async throws {
        databaseManager = nil
        // Cleanup is handled by super.tearDown() which calls TestDataCleanup.shared.cleanupAllTestData()
        try await super.tearDown()
    }

    func testFetchStartedMeetings() async throws {
        // Create a started meeting (started 10 minutes ago, ends in 20 minutes)
        let now = Date()
        let startedMeeting = try Event(
            id: "started-test-1",
            title: "Started Meeting Test",
            startDate: now.addingTimeInterval(-600), // 10 minutes ago
            endDate: now.addingTimeInterval(1200), // 20 minutes from now
            calendarId: "test-calendar",
            links: [XCTUnwrap(URL(string: "https://meet.google.com/test-link"))]
        )

        // Create an upcoming meeting (starts in 30 minutes)
        let upcomingMeeting = Event(
            id: "started-test-2",
            title: "Upcoming Meeting Test",
            startDate: now.addingTimeInterval(1800), // 30 minutes from now
            endDate: now.addingTimeInterval(3600), // 60 minutes from now
            calendarId: "test-calendar"
        )

        // Create an ended meeting (ended 5 minutes ago)
        let endedMeeting = Event(
            id: "started-test-3",
            title: "Ended Meeting Test",
            startDate: now.addingTimeInterval(-1800), // 30 minutes ago
            endDate: now.addingTimeInterval(-300), // 5 minutes ago
            calendarId: "test-calendar"
        )

        // Save all meetings
        try await databaseManager.saveEvents([startedMeeting, upcomingMeeting, endedMeeting])

        // Test fetchStartedMeetings returns only the started meeting
        let startedMeetings = try await databaseManager.fetchStartedMeetings(limit: 10)
        XCTAssertEqual(startedMeetings.count, 1, "Should return exactly 1 started meeting")
        XCTAssertEqual(startedMeetings.first?.id, "started-test-1", "Should return the started meeting")
        XCTAssertEqual(startedMeetings.first?.title, "Started Meeting Test")

        // Test fetchUpcomingEvents returns only the upcoming meeting
        let upcomingMeetings = try await databaseManager.fetchUpcomingEvents(limit: 10)
        let upcomingIds = upcomingMeetings.map(\.id)
        XCTAssertTrue(upcomingIds.contains("started-test-2"), "Should contain upcoming meeting")
        XCTAssertFalse(upcomingIds.contains("started-test-1"), "Should not contain started meeting")
        XCTAssertFalse(upcomingIds.contains("started-test-3"), "Should not contain ended meeting")

        print("✅ Started meetings functionality test passed")
    }

    func testGoogleMeetLinkDetection() async throws {
        // Create a started meeting with Google Meet link
        let now = Date()
        let meetingWithGoogleMeet = try Event(
            id: "started-test-google-meet",
            title: "Google Meet Test",
            startDate: now.addingTimeInterval(-300), // 5 minutes ago
            endDate: now.addingTimeInterval(1800), // 30 minutes from now
            calendarId: "test-calendar",
            links: [XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))]
        )

        try await databaseManager.saveEvents([meetingWithGoogleMeet])

        let startedMeetings = try await databaseManager.fetchStartedMeetings(limit: 10)
        XCTAssertEqual(startedMeetings.count, 1)

        let meeting = try XCTUnwrap(startedMeetings.first)
        XCTAssertTrue(meeting.isOnlineMeeting, "Should detect as online meeting")
        XCTAssertTrue(meeting.shouldShowJoinButton, "Should show join button for started meeting")
        XCTAssertNotNil(meeting.primaryLink, "Should have primary link")
        XCTAssertEqual(meeting.provider, .meet, "Should detect as Google Meet")

        print("✅ Google Meet link detection test passed")
    }

    func testJoinButtonTenMinuteWindow() async throws {
        let now = Date()

        // Create meetings at different time offsets
        let tooEarlyMeeting = try Event(
            id: "started-test-too-early",
            title: "Too Early Meeting",
            startDate: now.addingTimeInterval(900), // 15 minutes from now (outside 10-minute window)
            endDate: now.addingTimeInterval(1800), // 30 minutes from now
            calendarId: "test-calendar",
            links: [XCTUnwrap(URL(string: "https://meet.google.com/too-early"))]
        )

        let justInTimeMeeting = try Event(
            id: "started-test-just-in-time",
            title: "Just In Time Meeting",
            startDate: now.addingTimeInterval(300), // 5 minutes from now (within 10-minute window)
            endDate: now.addingTimeInterval(1800), // 30 minutes from now
            calendarId: "test-calendar",
            links: [XCTUnwrap(URL(string: "https://meet.google.com/just-in-time"))]
        )

        let startedMeeting = try Event(
            id: "started-test-started",
            title: "Started Meeting",
            startDate: now.addingTimeInterval(-300), // 5 minutes ago (started)
            endDate: now.addingTimeInterval(1200), // 20 minutes from now
            calendarId: "test-calendar",
            links: [XCTUnwrap(URL(string: "https://meet.google.com/started"))]
        )

        let endedMeeting = try Event(
            id: "started-test-ended",
            title: "Ended Meeting",
            startDate: now.addingTimeInterval(-1800), // 30 minutes ago
            endDate: now.addingTimeInterval(-300), // 5 minutes ago (ended)
            calendarId: "test-calendar",
            links: [XCTUnwrap(URL(string: "https://meet.google.com/ended"))]
        )

        try await databaseManager.saveEvents([
            tooEarlyMeeting, justInTimeMeeting, startedMeeting, endedMeeting,
        ])

        // Test join button visibility
        XCTAssertFalse(
            tooEarlyMeeting.shouldShowJoinButton,
            "Should NOT show join button for meeting >10 minutes away"
        )
        XCTAssertTrue(
            justInTimeMeeting.shouldShowJoinButton,
            "Should show join button for meeting within 10 minutes"
        )
        XCTAssertTrue(
            startedMeeting.shouldShowJoinButton, "Should show join button for started meeting"
        )
        XCTAssertFalse(
            endedMeeting.shouldShowJoinButton, "Should NOT show join button for ended meeting"
        )

        print("✅ Join button 10-minute window test passed")
    }
}
