import Foundation
import Testing
@testable import Unmissable

struct CalendarInfoTests {
    // MARK: - Default Values

    @Test
    func defaultValues() {
        let info = CalendarInfo(id: "cal-1", name: "Test")

        #expect(info.id == "cal-1")
        #expect(info.name == "Test")
        #expect(info.description == nil)
        #expect(!info.isSelected)
        #expect(!info.isPrimary)
        #expect(info.colorHex == nil)
        #expect(info.sourceProvider == .google, "Default provider should be Google")
        #expect(info.lastSyncAt == nil)
    }

    // MARK: - withSelection

    @Test
    func withSelectionCopiesAllFieldsAndUpdatesTimestamp() {
        let original = CalendarInfo(
            id: "cal-ws",
            name: "Work",
            description: "Work calendar",
            isSelected: false,
            isPrimary: true,
            colorHex: "#FF0000",
            sourceProvider: .apple,
            lastSyncAt: Date(timeIntervalSince1970: 1000),
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 600),
        )

        let selected = original.withSelection(true)

        // Selection should change
        #expect(selected.isSelected)

        // All other fields should be preserved
        #expect(selected.id == original.id)
        #expect(selected.name == original.name)
        #expect(selected.description == original.description)
        #expect(selected.isPrimary, "isPrimary should be preserved")
        #expect(selected.colorHex == original.colorHex)
        #expect(selected.sourceProvider == .apple)
        #expect(selected.lastSyncAt == original.lastSyncAt)
        #expect(selected.createdAt == original.createdAt, "createdAt should be preserved")

        // updatedAt should be refreshed to ~now
        #expect(
            selected.updatedAt > original.updatedAt,
            "updatedAt should be refreshed to current time",
        )
    }

    @Test
    func withSelectionFalseDeselectsCalendar() {
        let original = CalendarInfo(id: "cal-ds", name: "Deselect", isSelected: true)
        let deselected = original.withSelection(false)

        #expect(!deselected.isSelected)
        #expect(deselected.id == original.id)
    }

    // MARK: - Codable Round-Trip

    @Test
    func codableRoundTrip() throws {
        let original = CalendarInfo(
            id: "cal-codable",
            name: "Codable Test",
            description: "Round-trip test",
            isSelected: true,
            isPrimary: true,
            colorHex: "#1a73e8",
            sourceProvider: .apple,
            lastSyncAt: Date(timeIntervalSince1970: 2000),
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 1500),
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalendarInfo.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.description == original.description)
        #expect(decoded.isSelected == original.isSelected)
        #expect(decoded.isPrimary == original.isPrimary)
        #expect(decoded.colorHex == original.colorHex)
        #expect(decoded.sourceProvider == original.sourceProvider)
        #expect(decoded.lastSyncAt == original.lastSyncAt)
    }

    @Test
    func codableRoundTripWithNilOptionals() throws {
        let original = CalendarInfo(id: "cal-nil", name: "Nil Fields")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalendarInfo.self, from: data)

        #expect(decoded.description == nil)
        #expect(decoded.colorHex == nil)
        #expect(decoded.lastSyncAt == nil)
    }

    // MARK: - Identifiable

    @Test
    func identifiableConformanceUsesCalendarId() {
        let info = CalendarInfo(id: "unique-cal-id", name: "Test")
        #expect(info.id == "unique-cal-id")
    }

    @Test
    func withSelectionCodableRoundTrip() throws {
        let original = CalendarInfo(
            id: "cal-sel-rt",
            name: "Round Trip",
            description: "Test",
            isSelected: false,
            isPrimary: true,
            colorHex: "#1a73e8",
            sourceProvider: .apple,
        )

        let selected = original.withSelection(true)
        let data = try JSONEncoder().encode(selected)
        let decoded = try JSONDecoder().decode(CalendarInfo.self, from: data)

        #expect(decoded.isSelected, "Selection state should survive Codable round-trip")
        #expect(decoded.id == original.id)
        #expect(decoded.sourceProvider == .apple)
        #expect(decoded.isPrimary)
    }

    @Test
    func twoCalendarsWithSameIdShareIdentity() {
        let cal1 = CalendarInfo(id: "shared", name: "Calendar A", isSelected: true)
        let cal2 = CalendarInfo(id: "shared", name: "Calendar B", isSelected: false)

        #expect(cal1.id == cal2.id)
    }
}
