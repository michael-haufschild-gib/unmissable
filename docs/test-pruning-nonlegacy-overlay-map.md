# Non-Legacy Overlay Overlap Consolidation Map (Pass 2) - 2026-02-21

## Scope

Second-pass review of remaining non-legacy overlap with focus on `Overlay*Integration*` suites and nearby overlay/system overlap:

- `Tests/UnmissableTests/AppStateDisconnectCleanupTests.swift`
- `Tests/UnmissableTests/EventSchedulerSnoozePreservationTests.swift`
- `Tests/UnmissableTests/OverlayAccuracyAndInteractionTests.swift`
- `Tests/UnmissableTests/OverlayCompleteIntegrationTests.swift`
- `Tests/UnmissableTests/OverlayContentViewTests.swift`
- `Tests/UnmissableTests/OverlayFunctionalityIntegrationTests.swift`
- `Tests/UnmissableTests/OverlayManagerIntegrationTests.swift`
- `Tests/UnmissableTests/OverlayManagerTimerFixTest.swift`
- `Tests/UnmissableTests/OverlayRuntimeContractTests.swift`
- `Tests/UnmissableTests/OverlaySnapshotTests.swift`
- `Tests/UnmissableTests/OverlaySnoozeAndDismissTests.swift`
- `Tests/UnmissableTests/OverlayTimerLogicTests.swift`
- `Tests/UnmissableTests/OverlayUIInteractionValidationTests.swift`
- `Tests/UnmissableTests/StartedMeetingsTests.swift`
- `Tests/UnmissableTests/SystemIntegrationTests.swift`

## Overlap Evidence (Concrete)

Large overlap cluster (same lifecycle assertions repeated):

- `OverlayCompleteIntegrationTests.swift`: 13 tests, 420 lines, `showOverlay` x15, `hideOverlay` x10, `snoozeOverlay` x11
- `OverlayFunctionalityIntegrationTests.swift`: 8 tests, 497 lines, `showOverlay` x13, `hideOverlay` x12, `snoozeOverlay` x2, `startScheduling` x5
- `OverlayManagerIntegrationTests.swift`: 5 tests, 110 lines, `showOverlay` x5, `hideOverlay` x3, `snoozeOverlay` x2

These overlap heavily with already-compact contract suites:

- `OverlayRuntimeContractTests.swift`
- `OverlaySnoozeAndDismissTests.swift`
- `OverlayAccuracyAndInteractionTests.swift`
- `SystemIntegrationTests.swift`

## Keep/Delete Consolidation Map (Proposal Only)

No removals in this pass. This is a decision map for the next pruning step.

| File | Decision | Why | Unique Assertions To Preserve | Migration Target |
|---|---|---|---|---|
| `Tests/UnmissableTests/AppStateDisconnectCleanupTests.swift` | Keep | AppState boundary contract (disconnect clears overlay + popup) is unique | N/A | N/A |
| `Tests/UnmissableTests/EventSchedulerSnoozePreservationTests.swift` | Keep | Unique contract: preference reschedule must preserve future snooze alerts | N/A | N/A |
| `Tests/UnmissableTests/OverlayAccuracyAndInteractionTests.swift` | Keep | Strong timer/countdown correctness and responsiveness coverage | Add immediate-init assertion from timer-fix suite | Same file |
| `Tests/UnmissableTests/OverlayCompleteIntegrationTests.swift` | Delete after migration | Broad umbrella duplicates lifecycle/snooze/timer/interaction checks from other suites | Malformed-event resilience and repeated hide/snooze idempotence | `OverlayRuntimeContractTests.swift`, `OverlaySnoozeAndDismissTests.swift` |
| `Tests/UnmissableTests/OverlayContentViewTests.swift` | Keep (compact) | Better minimal callback contract than validation mega-suite | Absorb one concise callback-routing matrix test | Same file |
| `Tests/UnmissableTests/OverlayFunctionalityIntegrationTests.swift` | Delete after migration | Overlaps runtime + scheduling + snooze + focus/preferences/system integration tests | Complex event payload preservation (title/organizer/attendees/provider) | `OverlayAccuracyAndInteractionTests.swift` |
| `Tests/UnmissableTests/OverlayManagerIntegrationTests.swift` | Delete after migration | Duplicates basic show/hide/snooze lifecycle checks already covered elsewhere | `timeUntilMeeting == 0` immediately after hide | `OverlaySnoozeAndDismissTests.swift` |
| `Tests/UnmissableTests/OverlayManagerTimerFixTest.swift` | Delete after migration | Narrow fix-validation suite now overlaps timer/accuracy contracts | Countdown initializes immediately after show (no initial zero) | `OverlayAccuracyAndInteractionTests.swift` |
| `Tests/UnmissableTests/OverlayRuntimeContractTests.swift` | Keep | Compact modern runtime contract suite from pass 1 | N/A | N/A |
| `Tests/UnmissableTests/OverlaySnapshotTests.swift` | Delete | Snapshot assertions are commented out; current assertions are mostly `XCTAssertNotNil` and duplicate manager lifecycle checks | None worth preserving | N/A |
| `Tests/UnmissableTests/OverlaySnoozeAndDismissTests.swift` | Keep | Canonical snooze vs dismiss behavior, timer-stop, state-reset coverage | Add idempotence assertion from complete suite | Same file |
| `Tests/UnmissableTests/OverlayTimerLogicTests.swift` | Delete | Largely tests `Date` math/local helpers/mocks rather than production overlay runtime | None worth preserving | N/A |
| `Tests/UnmissableTests/OverlayUIInteractionValidationTests.swift` | Delete after migration | Overlaps callback tests in `OverlayContentViewTests` and contains low-signal callback-count checks | One compact callback-routing coverage test across event types | `OverlayContentViewTests.swift` |
| `Tests/UnmissableTests/StartedMeetingsTests.swift` | Keep | Database/meeting-window domain behavior; not part of overlay overlap cluster | N/A | N/A |
| `Tests/UnmissableTests/SystemIntegrationTests.swift` | Keep | High-value cross-component flow and reschedule/concurrency coverage | N/A | N/A |

## Planned Compact Set After This Pass

Primary overlay/system contract suites to keep as the compact non-legacy baseline:

1. `Tests/UnmissableTests/OverlayRuntimeContractTests.swift`
2. `Tests/UnmissableTests/OverlayAccuracyAndInteractionTests.swift`
3. `Tests/UnmissableTests/OverlaySnoozeAndDismissTests.swift`
4. `Tests/UnmissableTests/SystemIntegrationTests.swift`
5. `Tests/UnmissableTests/AppStateDisconnectCleanupTests.swift`
6. `Tests/UnmissableTests/EventSchedulerSnoozePreservationTests.swift`
7. `Tests/UnmissableTests/OverlayContentViewTests.swift`
8. `Tests/UnmissableTests/StartedMeetingsTests.swift`

## Removal Preconditions (Do Not Skip)

Before deleting any suite marked delete/delete-after-migration:

1. Migrate the listed unique assertions into destination keep suites.
2. Run focused tests for destination suites plus `SystemIntegrationTests`.
3. Remove only after migrated assertions are green and redundant behavior remains covered.

## Execution Status (2026-02-21)

- Migrated unique assertions into keep suites:
  - `OverlayRuntimeContractTests.swift`
  - `OverlayAccuracyAndInteractionTests.swift`
  - `OverlaySnoozeAndDismissTests.swift`
  - `OverlayContentViewTests.swift`
- Deleted overlap suites listed as delete/delete-after-migration in this map:
  - `OverlayCompleteIntegrationTests.swift`
  - `OverlayFunctionalityIntegrationTests.swift`
  - `OverlayManagerIntegrationTests.swift`
  - `OverlayManagerTimerFixTest.swift`
  - `OverlaySnapshotTests.swift`
  - `OverlayTimerLogicTests.swift`
  - `OverlayUIInteractionValidationTests.swift`
