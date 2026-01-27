# Unmissable — Snapshot for LLM Coding Agents

## System overview

- Platform: macOS 14+ SwiftUI menu bar app (SPM target `Unmissable`).
- Purpose: Full-screen meeting overlays for upcoming/ongoing events with join, snooze, and dismiss.
- Stack: Swift 6.0 with StrictConcurrency; SwiftUI + AppKit; GRDB (SQLite); AppAuth (OAuth2); KeychainAccess; Magnet (shortcuts).

## Architecture (components and responsibilities)

- AppState (@MainActor)
  - Central coordinator for services and UI-facing state.
  - Wires managers, starts scheduling and periodic sync, mirrors menu bar preview.
  - Public entry points: `connectToCalendar()`, `disconnectFromCalendar()`, `syncNow()`, `showPreferences()`, `showMeetingDetails(for:)`.

- CalendarService (@MainActor)
  - Owns `OAuth2Service`, `GoogleCalendarAPIService`, `DatabaseManager`, `SyncManager`.
  - Publishes: `isConnected`, `syncStatus`, `events`, `startedEvents`, `calendars`, `lastSyncTime`, `nextSyncTime`.
  - Loads cached data and maps via `TimezoneManager.localizedEvent` for display.

- SyncManager (@MainActor)
  - Periodic sync loop with network reachability; backoff with jitter on error.
  - Fetch window: start of today → +7 days.
  - On success: persists calendars/events, updates `lastSyncTime`/`nextSyncTime`, triggers `onSyncCompleted`.

- GoogleCalendarAPIService (@MainActor)
  - Calls Google Calendar REST endpoints with bearer tokens from `OAuth2Service`.
  - Fetches calendars and events for selected calendars; parses into internal `Event`.

- DatabaseManager (GRDB)
  - Local SQLite DB; schema version 3; creates/updates tables; FTS for events (title/organizer).
  - Query helpers for upcoming/started/ranged fetches and search; maintenance tasks.

- EventScheduler (@MainActor)
  - Builds `ScheduledAlert`s from events and `PreferencesManager`.
  - Schedules overlay shows and snoozes; monitors alerts every 5s.

- OverlayManager (@MainActor)
  - Manages per-display overlay NSWindows; countdown updates via 1s Task.
  - Handles actions (dismiss, snooze, join). Hides windows with `orderOut(nil)`.

- PreferencesManager (@MainActor)
  - UserDefaults-backed settings: alert timing, sync interval, theme, sound, display rules, menu bar.

- MenuBarPreviewManager (@MainActor)
  - Computes `menuBarText` and `shouldShowIcon` from upcoming events and preferences.

- TimezoneManager
  - Formats for display and copy-through mapping; does not mutate absolute Date values.

- FocusModeManager / ShortcutsManager / MeetingDetailsPopupManager / SoundManager
  - Focus gating, global shortcuts, meeting details popup, audio playback.

## Data flows

1. Authentication
   - `AppState.connectToCalendar()` → OAuth via `OAuth2Service` → `CalendarService` loads calendars → `SyncManager` persists selection.

2. Event sync
   - `SyncManager.performSync()` fetches events per selected calendar for [start of today … +7 days] via `GoogleCalendarAPIService`.
   - Parse to `Event` (preserve description, location, attendees, attachments, links, provider) → `DatabaseManager` saves.

3. UI state
   - `CalendarService.loadCachedData()` reads DB → `TimezoneManager.localizedEvent` (field-preserving) → publishes to UI.

4. Alerts/overlays
   - `AppState` calls `EventScheduler.startScheduling(events, overlayManager)`.
   - Scheduler triggers → `OverlayManager.showOverlay(event)`; 1s countdown; actions route back to `OverlayManager`.

## Google Calendar integration (APIs and config)

- Config (`GoogleCalendarConfig`)
  - Scopes: `calendar.readonly`, `calendarlist.readonly`, `userinfo.email`.
  - Client ID: env `GOOGLE_OAUTH_CLIENT_ID` or repo-root `Config.plist` key `GoogleOAuthClientID`.
  - Redirect scheme: env `GOOGLE_OAUTH_REDIRECT_SCHEME` or `RedirectScheme` (default `com.unmissable.app`); redirect URI `<scheme>:/`.

- Calendars
  - `GET /calendar/v3/users/me/calendarList` (Authorization: Bearer).
  - Default selection: primary calendar (toggle-able via preferences/UI).

- Events
  - Query items: `timeMin`, `timeMax`, `singleEvents=true`, `orderBy=startTime`, `maxResults=250`, `maxAttendees=100`, and:

```swift
URLQueryItem(
  name: "fields",
  value: "items(id,summary,start,end,organizer,description,location,attendees,attachments,hangoutLink,conferenceData,status),nextPageToken"
)
```

- Filters applied: ignore `status == cancelled`; drop events where attendee `isSelf` is declined.
- Meeting links: parsed from location, description, and conferenceData.entryPoints; deduplicated.

## Persistence (SQLite via GRDB)

- Schema: version 3.
- Tables
  - events
    - Columns: `id` (PK), `title`, `startDate`, `endDate`, `organizer?`, `description?`, `location?`, `attendees` (JSON), `attachments` (JSON), `isAllDay`, `calendarId`, `timezone`, `links` (JSON), `meetingLinks` (legacy/unused), `provider?`, `snoozeUntil?`, `autoJoinEnabled`, `createdAt`, `updatedAt`.
    - Indexes: `startDate`, `calendarId`. FTS virtual table `events_fts` (title, organizer).
  - calendars
    - Columns: `id` (PK), `name`, `description?`, `isSelected`, `isPrimary`, `colorHex?`, `lastSyncAt?`, `createdAt`, `updatedAt`.
- Maintenance: delete events older than 30 days; vacuum database.

## Models (data shapes)

- Event
  - id:String; title:String; startDate:Date; endDate:Date; organizer:String?; description:String?; location:String?; attendees:[Attendee]; attachments:[EventAttachment]; isAllDay:Bool; calendarId:String; timezone:String; links:[URL]; provider:Provider?; snoozeUntil:Date?; autoJoinEnabled:Bool; createdAt:Date; updatedAt:Date.
  - Derived: `primaryLink`, `isOnlineMeeting`, `shouldShowJoinButton` (true from 10 minutes before start until end).

- Attendee
  - name:String?; email:String; status:AttendeeStatus?; isOptional:Bool; isOrganizer:Bool; isSelf:Bool.

- EventAttachment
  - Provider/file metadata parsed from Google API; persisted as JSON in events table.

- CalendarInfo
  - id:String; name:String; description:String?; isSelected:Bool; isPrimary:Bool; colorHex:String?; lastSyncAt:Date?; createdAt:Date; updatedAt:Date.

- ScheduledAlert
  - id:UUID; event:Event; triggerDate:Date; alertType: reminder(minutesBefore) | meetingStart | snooze(until).

## UI and theming (strict rules)

- Use `@Environment(\.customDesign)` for all colors, fonts, spacing, corners, shadows.
- Use custom components: `CustomButton`, `CustomToggle`, `CustomCard`, `CustomPicker`, `CustomStatusIndicator`.
- Forbidden: system semantic colors/fonts (e.g., `.foregroundColor(.primary)`, `.font(.headline)`), unstyled system controls.
- Meeting details: `HTMLTextView` renders HTML; `AttachmentsView` opens URLs via `NSWorkspace.shared.open`.

## Concurrency, timing, and window rules

- Use `Task { ... }` with `Task.sleep` for countdowns, scheduling, snooze, periodic sync, and UI refresh. Do not add `Timer.scheduledTimer`.
- Execute all window/UI operations on the main actor; do not block button callbacks.
- UI callbacks must wrap work with `Task.detached { await MainActor.run { ... } }` when mutating UI/window state to avoid re-entrancy.
- Cancel all Tasks before window operations; never call `NSWindow.close()` on overlays—always `orderOut(nil)` after cleanup.

## Data integrity rules

- Always request required event fields and set `maxAttendees` to avoid truncation.
- When mapping events (e.g., `TimezoneManager.localizedEvent`), copy all fields: description, location, attendees, attachments, links, provider, flags, timestamps.
- Persist attendees/attachments/links as JSON; keep `timezone` as provided by API (no mutation of absolute dates).

## Constraints and pitfalls

- Overlay re-entrancy: do not show an overlay if one is already visible for the same event.
- Immediate show: if an alert time is in the past or within ~0.5s, show immediately.
- Snooze remains valid after meeting start; auto-hide thresholds differ for snoozed overlays.
- Offline behavior: `SyncManager` marks `offline` and retries with capped backoff.
- Database: use `DatabaseQueue`; run `performMaintenance()` periodically.
- Legacy DB column `meetingLinks` is unused by the model; use `links`.

## Public contracts (for feature work)

- CalendarService.connect()
  - Performs OAuth, loads calendars, starts periodic sync, loads cache; publishes `calendars`, `events`, `startedEvents`.

- SyncManager.startPeriodicSync()
  - Starts Task loop; `performSync()` updates DB; calls `onSyncCompleted` on success.

- EventScheduler.startScheduling(events, overlayManager)
  - Computes alerts; schedules shows/snoozes; runs 5s monitoring loop.

- OverlayManager.showOverlay(event) / hideOverlay()
  - Show overlay windows with 1s countdown; hide cancels tasks, clears state, and `orderOut(nil)` windows.

## Build/run prerequisites

- Target: `Unmissable`.
- OAuth client ID required via env `GOOGLE_OAUTH_CLIENT_ID` or repo-root `Config.plist` key `GoogleOAuthClientID`. Redirect scheme via env `GOOGLE_OAUTH_REDIRECT_SCHEME` or `RedirectScheme` (default `com.unmissable.app`).
