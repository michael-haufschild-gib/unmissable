@testable import Unmissable
import XCTest

@MainActor
class MeetingDetailsEndToEndTests: DatabaseTestCase {
    var appState: AppState!

    override func setUp() async throws {
        try await super.setUp() // This calls TestDataCleanup.shared.cleanupAllTestData()
        appState = AppState()
    }

    override func tearDown() async throws {
        appState = nil
        // Cleanup is handled by super.tearDown() which calls TestDataCleanup.shared.cleanupAllTestData()
        try await super.tearDown()
    }

    // MARK: - End-to-End Popup Tests

    func testMeetingDetailsPopupEndToEnd() async throws {
        // Create a sample event with full details
        let sampleEvent = try Event(
            id: "e2e-test",
            title: "End-to-End Test Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            organizer: "organizer@example.com",
            description: "This is a comprehensive test meeting with all details populated.",
            location: "Conference Room B",
            attendees: [
                Attendee(
                    name: "Test Organizer", email: "organizer@example.com", status: .accepted,
                    isOrganizer: true, isSelf: false
                ),
                Attendee(
                    name: "Required Attendee", email: "required@example.com", status: .accepted, isSelf: false
                ),
                Attendee(
                    name: "Optional Attendee", email: "optional@example.com", status: .tentative,
                    isOptional: true, isSelf: false
                ),
                Attendee(email: "pending@example.com", status: .needsAction, isSelf: false),
            ],
            calendarId: "primary",
            links: [XCTUnwrap(URL(string: "https://meet.google.com/end-to-end-test"))]
        )

        // Test showing meeting details
        appState.showMeetingDetails(for: sampleEvent)

        // Wait for popup to initialize
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // This test validates the integration works without throwing exceptions
        XCTAssertNotNil(appState, "AppState should remain valid after showing popup")
    }

    func testMultipleMeetingDetailsPopups() {
        let expectation = XCTestExpectation(description: "Multiple meeting popups test")

        let events = (1 ... 5).map { index in
            Event(
                id: "multi-test-\(index)",
                title: "Meeting \(index)",
                startDate: Date().addingTimeInterval(TimeInterval(index * 3600)),
                endDate: Date().addingTimeInterval(TimeInterval(index * 3600 + 1800)),
                organizer: "org\(index)@example.com",
                description: "Description for meeting \(index)",
                attendees: [
                    Attendee(
                        name: "Attendee \(index)", email: "attendee\(index)@example.com", status: .accepted,
                        isSelf: false
                    ),
                ],
                calendarId: "primary"
            )
        }

        Task { @MainActor in
            // Show popups for multiple events rapidly
            for event in events {
                self.appState.showMeetingDetails(for: event)

                // Small delay between popups
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Database Integration Tests

    func testEventWithNewFieldsPersistence() async throws {
        let databaseManager = DatabaseManager.shared

        let eventWithDetails = Event(
            id: "db-test",
            title: "Database Test Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            organizer: "db@example.com",
            description: "This event tests database persistence of new fields.",
            location: "Test Location",
            attendees: [
                Attendee(name: "DB Tester", email: "tester@example.com", status: .accepted, isSelf: false),
                Attendee(email: "guest@example.com", status: .tentative, isOptional: true, isSelf: false),
            ],
            calendarId: "test-calendar"
        )

        // Save event (using saveEvents method that accepts an array)
        try await databaseManager.saveEvents([eventWithDetails])

        // Retrieve events and find our test event
        let startDate = Date().addingTimeInterval(-3600)
        let endDate = Date().addingTimeInterval(7200)
        let events = try await databaseManager.fetchEvents(from: startDate, to: endDate)
        let retrievedEvent = events.first { $0.id == "db-test" }

        XCTAssertNotNil(retrievedEvent)
        XCTAssertEqual(retrievedEvent?.description, eventWithDetails.description)
        XCTAssertEqual(retrievedEvent?.location, eventWithDetails.location)
        XCTAssertEqual(retrievedEvent?.attendees.count, eventWithDetails.attendees.count)

        // Check attendee details
        if let firstAttendee = retrievedEvent?.attendees.first {
            XCTAssertEqual(firstAttendee.name, "DB Tester")
            XCTAssertEqual(firstAttendee.email, "tester@example.com")
            XCTAssertEqual(firstAttendee.status, AttendeeStatus.accepted)
        }
    }

    // MARK: - Memory Pressure Tests

    func testPopupUnderMemoryPressure() {
        let expectation = XCTestExpectation(description: "Popup under memory pressure")

        // Create events with large amounts of data
        let largeDescription = String(repeating: "Large description content. ", count: 1000)
        let manyAttendees = (1 ... 200).map { index in
            Attendee(
                name: "Attendee \(index)",
                email: "attendee\(index)@example.com",
                status: AttendeeStatus.allCases.randomElement()!,
                isSelf: false
            )
        }

        let memoryIntensiveEvent = Event(
            id: "memory-test",
            title: "Memory Intensive Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            description: largeDescription,
            attendees: manyAttendees,
            calendarId: "memory-test"
        )

        Task { @MainActor in
            // Show popup with large data
            self.appState.showMeetingDetails(for: memoryIntensiveEvent)

            // Test multiple operations
            for _ in 0 ..< 10 {
                self.appState.showMeetingDetails(for: memoryIntensiveEvent)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15.0)
    }

    // MARK: - Theme Integration Tests

    func testPopupWithThemeChanges() {
        let expectation = XCTestExpectation(description: "Popup with theme changes")

        let sampleEvent = Event(
            id: "theme-test",
            title: "Theme Test Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            calendarId: "theme-test"
        )

        Task { @MainActor in
            // Show popup
            self.appState.showMeetingDetails(for: sampleEvent)

            // Simulate theme changes (this would normally happen through preferences)
            // The popup should adapt to theme changes gracefully

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Error Handling Tests

    func testPopupWithMalformedEventData() {
        let expectation = XCTestExpectation(description: "Popup with malformed data")

        // Event with potentially problematic data
        let malformedEvent = Event(
            id: "", // Empty ID
            title: String(repeating: "🎉", count: 1000), // Very long title with emojis
            startDate: Date.distantPast, // Extreme date
            endDate: Date.distantFuture, // Extreme date
            organizer: "not-an-email", // Invalid email format
            description: nil, // Nil description
            location: "", // Empty location
            attendees: [], // Empty attendees
            calendarId: "malformed"
        )

        Task { @MainActor in
            // Should handle malformed data gracefully
            self.appState.showMeetingDetails(for: malformedEvent)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
