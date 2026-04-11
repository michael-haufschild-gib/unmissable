import Foundation

/// Per-event alert timing override. Stored in a separate database table
/// (`event_overrides`) so overrides survive calendar sync cycles — the
/// `replaceEvents(for:with:)` path does full delete-and-insert on the
/// `events` table, but never touches `event_overrides`.
///
/// Keyed by (eventId, calendarId) to support the same event ID appearing
/// in multiple calendars without collisions.
///
/// A value of `0` for `alertMinutes` means "no alert" — the event is
/// silently suppressed from overlay and sound scheduling.
nonisolated struct EventOverride: Identifiable, Codable, Equatable {
    /// The ID of the event this override applies to.
    let eventId: String

    /// The calendar that owns this event instance.
    let calendarId: String

    /// Minutes before the event start to trigger the alert.
    /// `0` means suppress all alerts for this event.
    let alertMinutes: Int

    /// Compound key for Identifiable conformance.
    var id: String {
        Self.compoundKey(eventId: eventId, calendarId: calendarId)
    }

    /// ASCII Unit Separator (U+001F) — delimiter between eventId and calendarId
    /// in the compound key. This C0 control character cannot appear in any
    /// production ID (Google Calendar IDs are RFC3986-compatible strings, Apple
    /// uses hex UUIDs, recurring instance IDs use `<baseId>_<ISO timestamp>` —
    /// none contain U+001F).
    static let compoundKeyDelimiter = "\u{001F}"

    /// Compound key used to look up overrides by (eventId, calendarId).
    /// Matches the format used by EventScheduler and AppState.
    ///
    /// The delimiter invariant is enforced defensively via `precondition` so a
    /// future provider that violates the assumption crashes loudly in debug/test
    /// instead of silently producing colliding keys. In release builds the
    /// precondition remains active (Swift's default) to preserve the invariant
    /// at the database boundary.
    static func compoundKey(eventId: String, calendarId: String) -> String {
        precondition(
            !eventId.contains(compoundKeyDelimiter)
                && !calendarId.contains(compoundKeyDelimiter),
            "EventOverride.compoundKey: eventId/calendarId must not contain U+001F",
        )
        return "\(eventId)\(compoundKeyDelimiter)\(calendarId)"
    }
}
