import Foundation
import Testing
@testable import Unmissable

struct CalendarProviderTypeTests {
    // MARK: - Display Names

    @Test
    func displayNamesAreHumanReadable() {
        #expect(CalendarProviderType.google.displayName == "Google Calendar")
        #expect(CalendarProviderType.apple.displayName == "Apple Calendar")
    }

    // MARK: - Icon Names

    @Test
    func iconNamesAreSFSymbols() {
        #expect(CalendarProviderType.google.iconName == "calendar")
        #expect(CalendarProviderType.apple.iconName == "apple.logo")
    }

    // MARK: - Connection Labels

    @Test
    func connectionLabelsIncludeProviderName() {
        #expect(CalendarProviderType.google.connectionLabel == "Connect Google Calendar")
        #expect(CalendarProviderType.apple.connectionLabel == "Connect Apple Calendar")
    }

    // MARK: - CaseIterable

    @Test
    func allCasesContainsBothProviders() {
        #expect(
            CalendarProviderType.allCases == [.google, .apple],
            "allCases should contain exactly google and apple in order",
        )
    }

    // MARK: - Codable

    @Test
    func codableRoundTrip() throws {
        for provider in CalendarProviderType.allCases {
            let data = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(CalendarProviderType.self, from: data)
            #expect(decoded == provider, "\(provider) should survive Codable round-trip")
        }
    }

    @Test
    func rawValueEncoding() throws {
        let data = try JSONEncoder().encode(CalendarProviderType.google)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json == "\"google\"")
    }

    @Test
    func decodingFromRawValue() throws {
        let json = Data("\"apple\"".utf8)
        let decoded = try JSONDecoder().decode(CalendarProviderType.self, from: json)
        #expect(decoded == .apple)
    }

    @Test
    func decodingInvalidRawValueThrows() {
        let json = Data("\"outlook\"".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CalendarProviderType.self, from: json)
        }
    }
}
