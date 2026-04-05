import Foundation
import Testing
@testable import Unmissable

struct AttendeeModelTests {
    // MARK: - Basic Model Tests

    @Test
    func attendeeInitialization() {
        let attendee = Attendee(
            name: "John Doe",
            email: "john@example.com",
            status: .accepted,
            isOptional: false,
            isOrganizer: true,
            isSelf: false,
        )

        #expect(attendee.name == "John Doe")
        #expect(attendee.email == "john@example.com")
        #expect(attendee.status == AttendeeStatus.accepted)
        #expect(!attendee.isOptional)
        #expect(attendee.isOrganizer)
        #expect(attendee.displayName == "John Doe")
    }

    @Test
    func attendeeWithoutName() {
        let attendee = Attendee(
            email: "noname@example.com",
            status: .needsAction,
            isSelf: false,
        )

        #expect(attendee.name == nil)
        #expect(attendee.email == "noname@example.com")
        #expect(attendee.status == AttendeeStatus.needsAction)
        #expect(!attendee.isOptional)
        #expect(!attendee.isOrganizer)
        #expect(attendee.displayName == "noname@example.com", "Should use email when name is nil")
    }

    @Test
    func attendeeDefaultValues() {
        let attendee = Attendee(email: "default@example.com", isSelf: false)

        #expect(attendee.name == nil)
        #expect(attendee.email == "default@example.com")
        #expect(attendee.status == nil)
        #expect(!attendee.isOptional)
        #expect(!attendee.isOrganizer)
        #expect(!attendee.isSelf)
        #expect(attendee.displayName == "default@example.com")
    }

    @Test
    func attendeeSelfField() {
        let currentUserAttendee = Attendee(
            email: "current@example.com",
            status: .accepted,
            isSelf: true,
        )

        let otherAttendee = Attendee(
            email: "other@example.com",
            status: .accepted,
            isSelf: false,
        )

        #expect(currentUserAttendee.isSelf)
        #expect(!otherAttendee.isSelf)
    }

    @Test
    func attendeeID_derivedFromEmail() {
        let organizerEntry = Attendee(
            name: "Organizer",
            email: "shared@example.com",
            status: .accepted,
            isOrganizer: true,
            isSelf: false,
        )
        let guestEntry = Attendee(
            name: "Guest",
            email: "shared@example.com",
            status: .accepted,
            isOrganizer: false,
            isSelf: false,
        )

        // Attendee.id is derived from email — same email = same identity
        #expect(organizerEntry.id == guestEntry.id)
        #expect(organizerEntry.id == "shared@example.com")
    }

    // MARK: - AttendeeStatus Tests

    @Test
    func attendeeStatusDisplayText() {
        #expect(AttendeeStatus.accepted.displayText == "Accepted")
        #expect(AttendeeStatus.declined.displayText == "Declined")
        #expect(AttendeeStatus.tentative.displayText == "Maybe")
        #expect(AttendeeStatus.needsAction.displayText == "Not responded")
    }

    @Test
    func attendeeStatusIconNames() {
        #expect(AttendeeStatus.accepted.iconName == "checkmark.circle.fill")
        #expect(AttendeeStatus.declined.iconName == "xmark.circle")
        #expect(AttendeeStatus.tentative.iconName == "questionmark.circle.fill")
        #expect(AttendeeStatus.needsAction.iconName == "questionmark.circle")
    }

    @Test
    func attendeeStatusRawValues() {
        #expect(AttendeeStatus.accepted.rawValue == "accepted")
        #expect(AttendeeStatus.declined.rawValue == "declined")
        #expect(AttendeeStatus.tentative.rawValue == "tentative")
        #expect(AttendeeStatus.needsAction.rawValue == "needsAction")
    }

    // MARK: - Codable Tests

    @Test
    func attendeeCodableEncoding() throws {
        let attendee = Attendee(
            name: "Test User",
            email: "test@example.com",
            status: .accepted,
            isOptional: true,
            isOrganizer: false,
            isSelf: true,
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(attendee)

        // Verify round-trip produces identical attendee instead of just checking .count
        let decoded = try JSONDecoder().decode(Attendee.self, from: data)
        #expect(decoded.email == "test@example.com", "Encoded data should round-trip correctly")
    }

    @Test
    func attendeeCodableDecoding() throws {
        let attendee = Attendee(
            name: "Test User",
            email: "test@example.com",
            status: .declined,
            isOptional: false,
            isOrganizer: true,
            isSelf: true,
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(attendee)

        let decoder = JSONDecoder()
        let decodedAttendee = try decoder.decode(Attendee.self, from: data)

        #expect(decodedAttendee.name == attendee.name)
        #expect(decodedAttendee.email == attendee.email)
        #expect(decodedAttendee.status == attendee.status)
        #expect(decodedAttendee.isOptional == attendee.isOptional)
        #expect(decodedAttendee.isOrganizer == attendee.isOrganizer)
        #expect(decodedAttendee.isSelf == attendee.isSelf)
        #expect(decodedAttendee.id == attendee.id)
    }

    @Test
    func attendeeArrayCodable() throws {
        let attendees = [
            Attendee(name: "User 1", email: "user1@example.com", status: .accepted, isSelf: false),
            Attendee(email: "user2@example.com", status: .tentative, isOptional: true, isSelf: false),
            Attendee(
                name: "Organizer",
                email: "org@example.com",
                status: .accepted,
                isOrganizer: true,
                isSelf: false,
            ),
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(attendees)

        let decoder = JSONDecoder()
        let decodedAttendees = try decoder.decode([Attendee].self, from: data)

        #expect(decodedAttendees.map(\.email) == attendees.map(\.email))

        for (original, decoded) in zip(attendees, decodedAttendees) {
            #expect(original.name == decoded.name)
            #expect(original.email == decoded.email)
            #expect(original.status == decoded.status)
            #expect(original.isOptional == decoded.isOptional)
            #expect(original.isOrganizer == decoded.isOrganizer)
            #expect(original.isSelf == decoded.isSelf)
        }
    }

    // MARK: - Equatable Tests

    @Test
    func equatable_sameFieldsAreEqual() {
        let a = Attendee(name: "Alice", email: "alice@x.com", status: .accepted, isSelf: false)
        let b = Attendee(name: "Alice", email: "alice@x.com", status: .accepted, isSelf: false)
        #expect(a == b)
    }

    @Test
    func equatable_differentStatusMakesNotEqual() {
        let a = Attendee(name: "Alice", email: "alice@x.com", status: .accepted, isSelf: false)
        let b = Attendee(name: "Alice", email: "alice@x.com", status: .declined, isSelf: false)
        #expect(a != b, "Different status should make attendees not equal")
    }

    @Test
    func equatable_differentNameSameEmailMakesNotEqual() {
        let a = Attendee(name: "Alice", email: "shared@x.com", isSelf: false)
        let b = Attendee(name: "Bob", email: "shared@x.com", isSelf: false)
        #expect(a != b, "Equatable compares all stored properties, not just email")
    }

    // MARK: - AttendeeStatus Edge Cases

    @Test
    func attendeeStatusCaseIterable() {
        #expect(
            AttendeeStatus.allCases ==
                [.needsAction, .declined, .tentative, .accepted],
        )
    }

    @Test
    func attendeeStatusCodableFromRawValue() throws {
        let json = Data("\"tentative\"".utf8)
        let decoded = try JSONDecoder().decode(AttendeeStatus.self, from: json)
        #expect(decoded == .tentative)
    }

    @Test
    func attendeeStatusCodableInvalidRawValueThrows() {
        let json = Data("\"unknown\"".utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AttendeeStatus.self, from: json) }
    }

    // MARK: - Edge Case Tests

    @Test
    func attendeeWithEmptyEmail() {
        let attendee = Attendee(name: "No Email", email: "", isSelf: false)

        #expect(attendee.email.isEmpty)
        #expect(attendee.displayName == "No Email", "Should use name when email is empty")
    }

    @Test
    func attendeeWithVeryLongName() {
        let longName = String(repeating: "Very Long Name ", count: 100)
        let attendee = Attendee(name: longName, email: "long@example.com", isSelf: false)

        #expect(attendee.name == longName)
        #expect(attendee.displayName == longName)
    }

    @Test
    func attendeeWithSpecialCharacters() {
        let specialName = "Jose Muller-Schmidt (special)"
        let specialEmail = "josé.müller+test@exämple-dömaın.cöm"

        let attendee = Attendee(name: specialName, email: specialEmail, isSelf: false)

        #expect(attendee.name == specialName)
        #expect(attendee.email == specialEmail)
        #expect(attendee.displayName == specialName)
    }
}
