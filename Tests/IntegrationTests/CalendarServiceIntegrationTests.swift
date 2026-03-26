@testable import Unmissable
import XCTest

final class CalendarServiceIntegrationTests: XCTestCase {
    private var calendarService: CalendarService!
    private var preferencesManager: PreferencesManager!
    private var databaseManager: DatabaseManager!
    private var tempDatabaseURL: URL!

    @MainActor
    override func setUp() async throws {
        // Use isolated temp database to avoid polluting production data
        let tempDir = FileManager.default.temporaryDirectory
        tempDatabaseURL = tempDir.appendingPathComponent(
            "unmissable-integration-\(UUID().uuidString).db"
        )
        databaseManager = DatabaseManager(databaseURL: tempDatabaseURL)

        preferencesManager = PreferencesManager(themeManager: ThemeManager())
        calendarService = CalendarService(
            preferencesManager: preferencesManager, databaseManager: databaseManager,
            linkParser: LinkParser()
        )
        try await super.setUp()
    }

    override func tearDown() async throws {
        calendarService = nil
        preferencesManager = nil
        databaseManager = nil
        if let url = tempDatabaseURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempDatabaseURL = nil
        try await super.tearDown()
    }

    @MainActor
    func testCalendarServiceInitialization() {
        XCTAssertFalse(calendarService.isConnected)
        XCTAssertEqual(calendarService.syncStatus, .idle)
        XCTAssertTrue(calendarService.events.isEmpty)
        XCTAssertTrue(calendarService.calendars.isEmpty)
    }

    @MainActor
    func testOAuth2StateExposedViaCalendarService() {
        XCTAssertFalse(calendarService.isConnected)
        XCTAssertNil(calendarService.userEmail)
        XCTAssertNil(calendarService.authError)
    }

    @MainActor
    func testCalendarSelectionUpdate() throws {
        let mockCalendar = CalendarInfo(
            id: "test-calendar",
            name: "Test Calendar",
            isSelected: false,
            isPrimary: false
        )

        calendarService.calendars = [mockCalendar]
        calendarService.updateCalendarSelection("test-calendar", isSelected: true)

        let updatedCalendar = try XCTUnwrap(
            calendarService.calendars.first { $0.id == "test-calendar" }
        )
        XCTAssertTrue(updatedCalendar.isSelected)
    }

    @MainActor
    func testSyncWithoutConnection() async {
        await calendarService.syncEvents()

        XCTAssertTrue(
            calendarService.syncStatus == .idle || calendarService.syncStatus == .offline
        )
    }

    @MainActor
    func testDisconnectAll() async {
        await calendarService.disconnectAll()

        XCTAssertFalse(calendarService.isConnected)
        XCTAssertTrue(calendarService.events.isEmpty)
        XCTAssertTrue(calendarService.calendars.isEmpty)
    }
}
