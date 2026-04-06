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

    /// Compound key used to look up overrides by (eventId, calendarId).
    /// Matches the format used by EventScheduler and AppState.
    ///
    /// The `_` separator is safe because calendar IDs always contain `@`
    /// (Google) or are UUIDs (Apple), making collisions with event ID
    /// suffixes impossible in practice.
    static func compoundKey(eventId: String, calendarId: String) -> String {
        "\(eventId)_\(calendarId)"
    }
}
