# Debugging Guide

**Purpose**: How to use the diagnostics system when debugging Unmissable.

---

## Overview

Unmissable has a structured diagnostics layer that captures correlated events across
startup, auth, sync, database, scheduler, notification, and overlay subsystems.

| Layer | Always On | Deep Diagnostics Only |
|-------|-----------|----------------------|
| OSLog (Console.app) | info/warning/error | structured records via `Diagnostics` category |
| FlightRecorder (in-memory) | No | Yes — 500-record ring buffer |
| Session trace (JSONL file) | No | On-demand export |
| Bug book (markdown) | No | On-demand export / auto on E2E failure |

---

## Gating

| Build | Deep Diagnostics Default | Override |
|-------|-------------------------|----------|
| DEBUG (Xcode Debug configuration) | **Enabled** | Always on |
| Release (Xcode Release configuration) | **Disabled** | Set env `UNMISSABLE_DIAGNOSTICS=1` or UserDefaults key `com.unmissable.diagnostics.enabled` |
| Tests | **Enabled** | Always on |

---

## Launching with Diagnostics

```bash
# Standard dev launch (diagnostics enabled by default in debug)
./Scripts/run-dev.sh

# Release build with diagnostics override (-n forces new instance)
UNMISSABLE_DIAGNOSTICS=1 open -n ./Unmissable.app
```

---

## Reading Diagnostics

### Console.app

Filter by:
- **Subsystem**: `com.unmissable.app`
- **Category**: `Diagnostics` (structured records) or any manager name (e.g., `SyncManager`)

Structured records appear as single-line summaries:

```text
SyncManager.sync.preconditions=info flow=a1b2c3d4 provider=google selectedCalendars=3 attempt=1 isManual=false
```

### Flight Recorder

The in-memory ring buffer holds the most recent 500 structured records.
Access programmatically:

```swift
// Snapshot all records
let records = AppDiagnostics.recorder.snapshot()

// Export as JSONL
try AppDiagnostics.recorder.exportJSONL(to: url)

// Recent tail
let recent = AppDiagnostics.recorder.tail(20)
```

### Bug Book (Markdown Report)

Generate a human-readable diagnostic report:

```swift
let report = DiagnosticsBookExporter.export(
    stateSnapshot: ["overlayVisible": "true", "alerts": "3"],
    testContext: ["testName": "testSyncFlow"]
)
```

---

## What Is Logged

### Always (all builds via OSLog)

- App launch / terminate
- Calendar connect / disconnect
- Sync start / complete / error
- Overlay show / hide
- Notification delivery success / failure
- Health status changes

### Deep Diagnostics Only

- Per-calendar fetch outcomes (success with count, failure with redacted error)
- Alert scheduling decisions (why each event was scheduled, skipped, or missed)
- Overlay suppression reasons (focus mode, smart suppression, age threshold)
- Flow correlation (sync cycle as a single story with flow ID)
- State snapshots (calendar counts, event counts, override counts)
- Theme and menu bar state transitions

---

## Correlation

Each diagnostic record carries:

| Field | Purpose |
|-------|---------|
| `sessionId` | Groups all records from one app launch |
| `flowId` | Correlates records within one operation (e.g., one sync cycle) |
| `component` | Which subsystem (e.g., `SyncManager`, `EventScheduler`) |
| `phase` | Step within the operation (e.g., `sync.start`, `sync.fetchResults`, `sync.end`) |
| `outcome` | `success`, `failure`, `skipped`, or `info` |
| `durationMs` | Wall-clock duration for flow start/end pairs |

To follow one sync cycle in Console.app, filter by the flow ID prefix shown in the
`flow=` field of the start record.

---

## Redaction

All diagnostic output is redacted. Sensitive fields are never logged in full:

| Data Type | Redaction | Example |
|-----------|-----------|---------|
| Calendar ID | First 2 chars + `***@domain` | `us***@gmail.com` |
| Event ID | First 6 chars + `…` | `abc123…` |
| Email | First 2 chars + `***@domain` | `jo***@company.com` |
| URL | Scheme + host only | `https://meet.google.com/***` |
| File path | Last 2 components | `…/unmissable/db.sqlite` |
| Title | First 30 chars + length | `Team Standup…[45 chars]` |
| Error | Truncated at 120 chars | Full text up to limit |

---

## E2E Test Failures

When an E2E assertion fails (e.g., `waitForOverlay`), the failure message
automatically includes a diagnostic dump with:

- Scheduled alerts (count and details)
- Overlay visibility and active event
- Clock time (simulated)
- Recent flight recorder entries
- Flow summaries (in-progress and completed)

This eliminates the need to manually investigate "Overlay not visible" failures.
