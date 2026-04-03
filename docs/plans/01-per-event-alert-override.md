# Per-Event Alert Override

## Summary

Allow users to set a custom alert time on individual events, overriding the global default and length-based timing rules. Some meetings are critical (client calls, interviews), others are low-priority (optional standups). Users should be able to right-click or long-press an event in the menu bar list to set a per-event override.

## Why This Matters

In Your Face has this feature and users cite it as a reason they stay subscribed. The current system only offers global defaults (1-15 min) and length-based timing (short/medium/long). A user who has a critical client call at 2pm and an optional standup at 3pm gets the same alert timing for both. The override lets the user say "alert me 10 minutes early for the client call, 1 minute for the standup."

## Current State

### Alert timing flow

`EventScheduler.swift` calls `preferencesManager.alertMinutes(for:)` to determine per-event timing. That method (`PreferencesManager.swift:382-392`) checks `useLengthBasedTiming` and routes to `shortMeetingAlertMinutes`, `mediumMeetingAlertMinutes`, or `longMeetingAlertMinutes` based on event duration. There is no per-event field consulted.

### Event model

`Event.swift` already has a `snoozeUntil: Date?` field and an `autoJoinEnabled: Bool` field, both persisted in the database via `DatabaseModels.swift`. The pattern for adding a per-event override field already exists.

### Database

`DatabaseManager.swift` uses GRDB with migrations (`v1` through `v5`). Adding a new column requires a `v6` migration.

### UI entry point

`MenuBarView.swift:412-419` renders `CustomEventRow` for each event. Tapping an event calls `appState.showMeetingDetails(for: event)`. There is currently no right-click/context menu on event rows.

## Implementation Plan

### 1. Add `alertOverrideMinutes` to the Event model

**File:** `Sources/Unmissable/Models/Event.swift`

Add an optional `alertOverrideMinutes: Int?` field to the `Event` struct. When non-nil, it overrides all other alert timing logic. Default is `nil` (use global/length-based rules).

### 2. Database migration

**File:** `Sources/Unmissable/Core/DatabaseManager.swift`

Add a `v6-alertOverride` migration that adds an `alertOverrideMinutes` integer column (nullable) to the events table.

**File:** `Sources/Unmissable/Core/DatabaseModels.swift`

Add `Columns.alertOverrideMinutes` and handle encoding/decoding in the `Event` GRDB extension.

### 3. Modify alert timing resolution

**File:** `Sources/Unmissable/Features/Preferences/PreferencesManager.swift`

Change `alertMinutes(for:)` to check `event.alertOverrideMinutes` first:

```swift
func alertMinutes(for event: Event) -> Int {
    if let override = event.alertOverrideMinutes {
        return override
    }
    guard useLengthBasedTiming else {
        return defaultAlertMinutes
    }
    // ... existing length-based logic
}
```

### 4. Add context menu to event rows

**File:** `Sources/Unmissable/App/MenuBarView.swift`

Add a `.contextMenu` modifier to `CustomEventRow` with alert timing options:

- "Default timing" (clears override)
- "1 minute before"
- "2 minutes before"
- "5 minutes before"
- "10 minutes before"
- "15 minutes before"
- "No alert" (special value, e.g. `0`)

The context menu action should:
1. Save the override to the database (new `DatabaseManaging` method: `updateEventAlertOverride(_:minutes:)`)
2. Trigger a reschedule via `EventScheduler`

### 5. Visual indicator for overridden events

**File:** `Sources/Unmissable/App/MenuBarView.swift`

Show a small bell icon or timing badge on events that have a custom override, so users can see at a glance which events are customized.

### 6. Show override in meeting details

**File:** `Sources/Unmissable/Features/MeetingDetails/MeetingDetailsView.swift`

Display the current alert timing (whether default, length-based, or overridden) in the meeting info section. Allow changing it from there too.

## Key Design Decisions

- **Overrides are per-event-instance, not per-recurring-series.** This matches In Your Face's behavior and avoids the complexity of recurring event identity.
- **Overrides are stored locally** in the SQLite database, not pushed to the calendar provider. They survive sync cycles because `replaceEvents(for:with:)` does a full replace — the migration must ensure the override column is preserved during sync. Consider: sync replaces events atomically per calendar. The override must be read from the existing row and merged into the replacement event, or stored in a separate table keyed by event ID.
- **Separate table may be cleaner.** A dedicated `event_overrides` table with `(eventId TEXT PRIMARY KEY, alertOverrideMinutes INTEGER)` avoids the merge problem entirely. `alertMinutes(for:)` would check this table first.

## Testing

- Unit test: `alertMinutes(for:)` returns override when set, falls back to length-based/default when nil
- Unit test: override survives a sync cycle (event replaced, override preserved)
- Integration test: context menu sets override, next alert fires at overridden time
- E2E test: full flow from context menu to overlay appearance at custom time

## Estimated Scope

Medium. Touches model, database, scheduler, and two UI files. The separate-table approach is cleaner but adds a DB lookup per event during scheduling.
