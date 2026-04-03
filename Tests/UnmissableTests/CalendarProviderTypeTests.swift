@testable import Unmissable
import XCTest

final class CalendarProviderTypeTests: XCTestCase {
    // MARK: - Display Names

    func testDisplayNamesAreHumanReadable() {
        XCTAssertEqual(CalendarProviderType.google.displayName, "Google Calendar")
        XCTAssertEqual(CalendarProviderType.apple.displayName, "Apple Calendar")
    }

    // MARK: - Icon Names

    func testIconNamesAreSFSymbols() {
        XCTAssertEqual(CalendarProviderType.google.iconName, "calendar")
        XCTAssertEqual(CalendarProviderType.apple.iconName, "apple.logo")
    }

    // MARK: - Connection Labels

    func testConnectionLabelsIncludeProviderName() {
        XCTAssertEqual(CalendarProviderType.google.connectionLabel, "Connect Google Calendar")
        XCTAssertEqual(CalendarProviderType.apple.connectionLabel, "Connect Apple Calendar")
    }

    // MARK: - CaseIterable

    func testAllCasesContainsBothProviders() {
        XCTAssertEqual(
            CalendarProviderType.allCases,
            [.google, .apple],
            "allCases should contain exactly google and apple in order",
        )
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        for provider in CalendarProviderType.allCases {
            let data = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(CalendarProviderType.self, from: data)
            XCTAssertEqual(decoded, provider, "\(provider) should survive Codable round-trip")
        }
    }

    func testRawValueEncoding() throws {
        let data = try JSONEncoder().encode(CalendarProviderType.google)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, "\"google\"")
    }

    func testDecodingFromRawValue() throws {
        let json = Data("\"apple\"".utf8)
        let decoded = try JSONDecoder().decode(CalendarProviderType.self, from: json)
        XCTAssertEqual(decoded, .apple)
    }

    func testDecodingInvalidRawValueThrows() {
        let json = Data("\"outlook\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CalendarProviderType.self, from: json))
    }
}
