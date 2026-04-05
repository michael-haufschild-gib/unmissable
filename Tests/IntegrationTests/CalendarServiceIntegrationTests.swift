import Foundation
import Testing
@testable import Unmissable

@MainActor
struct CalendarServiceIntegrationTests {
    private let calendarService: CalendarService
    private let preferencesManager: PreferencesManager
    private let databaseManager: DatabaseManager

    init() {
        // Use isolated temp database to avoid polluting production data
        let tempDir = FileManager.default.temporaryDirectory
        let tempDatabaseURL = tempDir.appendingPathComponent(
            "unmissable-integration-\(UUID().uuidString).db",
        )
        databaseManager = DatabaseManager(databaseURL: tempDatabaseURL)

        preferencesManager = PreferencesManager(themeManager: ThemeManager())
        calendarService = CalendarService(
            preferencesManager: preferencesManager,
            databaseManager: databaseManager,
            linkParser: LinkParser(),
        )
    }

    @Test
    func calendarServiceInitialization() {
        #expect(!calendarService.isConnected)
        #expect(calendarService.syncStatus == .idle)
        #expect(calendarService.events.isEmpty)
        #expect(calendarService.calendars.isEmpty)
    }

    @Test
    func oAuth2StateExposedViaCalendarService() {
        #expect(!calendarService.isConnected)
        #expect(calendarService.userEmail == nil)
        #expect(calendarService.authError == nil)
    }

    @Test
    func calendarSelectionUpdate() throws {
        let mockCalendar = CalendarInfo(
            id: "test-calendar",
            name: "Test Calendar",
            isSelected: false,
            isPrimary: false,
        )

        calendarService.calendars = [mockCalendar]
        calendarService.updateCalendarSelection("test-calendar", isSelected: true)

        let updatedCalendar = try #require(
            calendarService.calendars.first { $0.id == "test-calendar" },
        )
        #expect(updatedCalendar.isSelected)
    }

    @Test
    func syncWithoutConnection() async {
        await calendarService.syncEvents()

        #expect(
            calendarService.syncStatus == .idle || calendarService.syncStatus == .offline,
        )
    }

    @Test
    func disconnectAll() async {
        await calendarService.disconnectAll()

        #expect(!calendarService.isConnected)
        #expect(calendarService.events.isEmpty)
        #expect(calendarService.calendars.isEmpty)
    }
}
