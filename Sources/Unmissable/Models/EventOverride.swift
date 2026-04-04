import Foundation

/// Per-event alert timing override. Stored in a separate database table
/// (`event_overrides`) so overrides survive calendar sync cycles — the
/// `replaceEvents(for:with:)` path does full delete-and-insert on the
/// `events` table, but never touches `event_overrides`.
///
/// A value of `0` for `alertMinutes` means "no alert" — the event is
/// silently suppressed from overlay and sound scheduling.
nonisolated struct EventOverride: Identifiable, Codable, Equatable {
    /// The ID of the event this override applies to.
    let eventId: String

    /// Minutes before the event start to trigger the alert.
    /// `0` means suppress all alerts for this event.
    let alertMinutes: Int

    var id: String {
        eventId
    }
}
