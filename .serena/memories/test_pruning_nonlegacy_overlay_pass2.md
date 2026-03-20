# Non-legacy overlay pruning pass 2 (2026-02-21)

Decision map documented in docs/test-pruning-nonlegacy-overlay-map.md.

Keep set (compact baseline):
- Tests/UnmissableTests/OverlayRuntimeContractTests.swift
- Tests/UnmissableTests/OverlayAccuracyAndInteractionTests.swift
- Tests/UnmissableTests/OverlaySnoozeAndDismissTests.swift
- Tests/UnmissableTests/SystemIntegrationTests.swift
- Tests/UnmissableTests/AppStateDisconnectCleanupTests.swift
- Tests/UnmissableTests/EventSchedulerSnoozePreservationTests.swift
- Tests/UnmissableTests/OverlayContentViewTests.swift
- Tests/UnmissableTests/StartedMeetingsTests.swift

Delete after migration:
- OverlayCompleteIntegrationTests.swift
- OverlayFunctionalityIntegrationTests.swift
- OverlayManagerIntegrationTests.swift
- OverlayManagerTimerFixTest.swift
- OverlayUIInteractionValidationTests.swift

Delete (no useful unique contracts):
- OverlaySnapshotTests.swift (snapshot asserts commented out, mostly not-nil)
- OverlayTimerLogicTests.swift (date math/mock/helper heavy)

Required migrations before deletion:
- malformed event + idempotent hide/snooze assertions into runtime/snooze suites
- immediate timer-init assertion into OverlayAccuracyAndInteractionTests
- timeUntilMeeting reset-on-hide assertion into OverlaySnoozeAndDismissTests
- compact callback routing matrix into OverlayContentViewTests
- complex event payload preservation assertion into OverlayAccuracyAndInteractionTests
