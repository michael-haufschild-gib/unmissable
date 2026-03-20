# Legacy-Style Test Pruning Map (2026-02-21)

## Decision Summary

- Reviewed 23 legacy-style files (`Migration`, `Deadlock`, `Reproduction`, `FixValidation`, `Production`, `Comprehensive`).
- Kept 2 high-value suites with direct product contracts.
- Deleted 21 legacy-style suites and replaced their unique runtime behaviors with one compact modern suite:
  - `Tests/UnmissableTests/OverlayRuntimeContractTests.swift`

## Compact Modern Coverage Added

`OverlayRuntimeContractTests` now covers the unique runtime assertions that were previously scattered across many legacy suites:

1. Future events schedule without immediate display.
2. Scheduled overlays fire near expected trigger time.
3. Multiple scheduled overlays fire sequentially.
4. Hiding active overlay does not cancel pending schedules.
5. Rapid show/hide cycles remain responsive.
6. Concurrent show/hide operations complete without inconsistent final state.
7. Ended events are ignored unless surfaced from snooze flow.

## Keep/Delete Map (All 23 Files)

| File | Decision | Rationale | Migration / Existing Coverage |
|---|---|---|---|
| `AsyncDispatchDeadlockFixTest.swift` | Delete | Deadlock-focused variant with overlapping show/hide timing assertions | Migrated to `OverlayRuntimeContractTests` (`testRapidShowHideCycleRemainsResponsive`, `testConcurrentShowHideOperationsRemainConsistent`) |
| `ComprehensiveOverlayTest.swift` | Delete | Broad stress/memory checklist overlaps multiple suites | Migrated critical runtime assertions to `OverlayRuntimeContractTests` |
| `ComprehensiveUICallbackTest.swift` | Delete | Callback deadlock checks duplicate existing callback tests | Existing: `OverlayContentViewTests`; runtime resilience in `OverlayRuntimeContractTests` |
| `CountdownTimerMigrationTests.swift` | Delete | Migration-phase timer checks heavily overlap modern overlay timer/accuracy suites | Existing: `OverlayAccuracyAndInteractionTests`, `OverlayTimerLogicTests` |
| `CriticalOverlayDeadlockTest.swift` | Delete | Deadlock reproduction with timing loops; high overlap | Migrated to compact runtime responsiveness/concurrency tests |
| `DatabaseManagerComprehensiveTests.swift` | Keep | Still high-value DB persistence/query/performance contract | Kept as-is |
| `DismissDeadlockFixValidationTest.swift` | Delete | Fix-validation duplicate of deadlock responsiveness behavior | Migrated to `OverlayRuntimeContractTests` |
| `EndToEndDeadlockPreventionTests.swift` | Delete | Oversized E2E deadlock umbrella with overlap across scheduler/overlay suites | Unique runtime pieces migrated; integration already covered by `SystemIntegrationTests` and `OverlayFunctionalityIntegrationTests` |
| `EventSchedulerComprehensiveTests.swift` | Keep | Core scheduler behavior contract (alerts, snooze preservation, preference impact) | Kept as-is |
| `OverlayBugReproductionTests.swift` | Delete | Reproduction-era timer/data checks overlap current accuracy suites | Existing: `OverlayAccuracyAndInteractionTests`, `OverlayTimerLogicTests`; runtime additions in `OverlayRuntimeContractTests` |
| `OverlayDeadlockReproductionTest.swift` | Delete | Reproduction-only deadlock harness | Covered by compact runtime suite |
| `OverlayDeadlockSimpleTest.swift` | Delete | Simple reproduction harness with weak assertions | Covered by compact runtime suite |
| `OverlayManagerComprehensiveTests.swift` | Delete | Broad overlap with integration/accuracy/snooze suites | Existing: `OverlayManagerIntegrationTests`, `OverlaySnoozeAndDismissTests`, `OverlayAccuracyAndInteractionTests` |
| `OverlayTimerFixValidationTests.swift` | Delete | Fix-validation overlap with timer logic/accuracy suites | Existing: `OverlayTimerLogicTests`, `OverlayAccuracyAndInteractionTests` |
| `ProductionDismissDeadlockTest.swift` | Delete | Production-repro timing harness, mostly duplicate of deadlock checks | Migrated to compact runtime suite |
| `ProductionSnoozeEndToEndTest.swift` | Delete | Production-repro variants overlap snooze integration tests | Existing: `OverlaySnoozeAndDismissTests`, `SnoozeAfterMeetingStartTest`, `SystemIntegrationTests` |
| `ScheduleTimerMigrationTests.swift` | Delete | Migration-specific schedule timing suite; replaced by direct runtime scheduling contract tests | Migrated to `OverlayRuntimeContractTests` (`testScheduledOverlayAppearsNearExpectedTriggerTime`, `testMultipleScheduledOverlaysCanFireSequentially`, `testFutureEventIsScheduledWithoutImmediateDisplay`) |
| `SnoozeTimerMigrationTests.swift` | Delete | Migration-specific snooze timing overlaps modern snooze suites | Existing: `OverlaySnoozeAndDismissTests`, `SnoozeAfterMeetingStartTest` |
| `TimerInvalidationDeadlockTest.swift` | Delete | Synthetic timer deadlock harness not tied to current production paths | Runtime responsiveness/concurrency retained in compact suite |
| `TimerMigrationTestHelpers.swift` | Delete | Only used by migration suites being removed | Replaced by local async polling helpers in compact tests |
| `UIComponentComprehensiveTests.swift` | Delete | Large amount of low-signal `XCTAssertNotNil` and duplicated UI checks | Existing focused UI tests: `OverlayContentViewTests`, snapshot suites |
| `UIInteractionDeadlockTest.swift` | Delete | Deadlock harness overlap with callback and runtime suites | Existing callback coverage + compact runtime suite |
| `WindowServerDeadlockTest.swift` | Delete | Deadlock scenario in test mode overlaps modern runtime responsiveness checks | Covered by compact runtime suite |

