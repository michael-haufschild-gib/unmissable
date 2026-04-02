@testable import Unmissable
import XCTest

final class CalendarInfoTests: XCTestCase {
    // MARK: - Default Values

    func testDefaultValues() {
        let info = CalendarInfo(id: "cal-1", name: "Test")

        XCTAssertEqual(info.id, "cal-1")
        XCTAssertEqual(info.name, "Test")
        XCTAssertNil(info.description)
        XCTAssertFalse(info.isSelected)
        XCTAssertFalse(info.isPrimary)
        XCTAssertNil(info.colorHex)
        XCTAssertEqual(info.sourceProvider, .google, "Default provider should be Google")
        XCTAssertNil(info.lastSyncAt)
    }

    // MARK: - withSelection

    func testWithSelectionCopiesAllFieldsAndUpdatesTimestamp() {
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
            updatedAt: Date(timeIntervalSince1970: 600)
        )

        let selected = original.withSelection(true)

        // Selection should change
        XCTAssertTrue(selected.isSelected)

        // All other fields should be preserved
        XCTAssertEqual(selected.id, original.id)
        XCTAssertEqual(selected.name, original.name)
        XCTAssertEqual(selected.description, original.description)
        XCTAssertTrue(selected.isPrimary, "isPrimary should be preserved")
        XCTAssertEqual(selected.colorHex, original.colorHex)
        XCTAssertEqual(selected.sourceProvider, .apple)
        XCTAssertEqual(selected.lastSyncAt, original.lastSyncAt)
        XCTAssertEqual(selected.createdAt, original.createdAt, "createdAt should be preserved")

        // updatedAt should be refreshed to ~now
        XCTAssertGreaterThan(
            selected.updatedAt, original.updatedAt,
            "updatedAt should be refreshed to current time"
        )
    }

    func testWithSelectionFalseDeselectsCalendar() {
        let original = CalendarInfo(id: "cal-ds", name: "Deselect", isSelected: true)
        let deselected = original.withSelection(false)

        XCTAssertFalse(deselected.isSelected)
        XCTAssertEqual(deselected.id, original.id)
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
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
            updatedAt: Date(timeIntervalSince1970: 1500)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalendarInfo.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.isSelected, original.isSelected)
        XCTAssertEqual(decoded.isPrimary, original.isPrimary)
        XCTAssertEqual(decoded.colorHex, original.colorHex)
        XCTAssertEqual(decoded.sourceProvider, original.sourceProvider)
        XCTAssertEqual(decoded.lastSyncAt, original.lastSyncAt)
    }

    func testCodableRoundTripWithNilOptionals() throws {
        let original = CalendarInfo(id: "cal-nil", name: "Nil Fields")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalendarInfo.self, from: data)

        XCTAssertNil(decoded.description)
        XCTAssertNil(decoded.colorHex)
        XCTAssertNil(decoded.lastSyncAt)
    }

    // MARK: - Identifiable

    func testIdentifiableConformanceUsesCalendarId() {
        let info = CalendarInfo(id: "unique-cal-id", name: "Test")
        XCTAssertEqual(info.id, "unique-cal-id")
    }

    func testWithSelectionCodableRoundTrip() throws {
        let original = CalendarInfo(
            id: "cal-sel-rt",
            name: "Round Trip",
            description: "Test",
            isSelected: false,
            isPrimary: true,
            colorHex: "#1a73e8",
            sourceProvider: .apple
        )

        let selected = original.withSelection(true)
        let data = try JSONEncoder().encode(selected)
        let decoded = try JSONDecoder().decode(CalendarInfo.self, from: data)

        XCTAssertTrue(decoded.isSelected, "Selection state should survive Codable round-trip")
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.sourceProvider, .apple)
        XCTAssertTrue(decoded.isPrimary)
    }

    func testTwoCalendarsWithSameIdShareIdentity() {
        let cal1 = CalendarInfo(id: "shared", name: "Calendar A", isSelected: true)
        let cal2 = CalendarInfo(id: "shared", name: "Calendar B", isSelected: false)

        XCTAssertEqual(cal1.id, cal2.id)
    }
}
