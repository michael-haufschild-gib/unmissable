SystemIntegrationTests stabilization note (2026-02-21):

Root cause for failures at lines 213, 216, 326 was mismatch between test expectation and OverlayManager scheduling semantics.
- OverlayManager.showOverlay(for:) defaults to minutesBeforeMeeting=5.
- For events far in the future (+10min, +40min), showOverlay schedules future display and does not immediately set activeEvent/isOverlayVisible.

Fix in Tests/UnmissableTests/SystemIntegrationTests.swift:
- testOverlappingEventsHandling: pass minutesBeforeMeeting: 60 on both showOverlay calls so test intentionally forces immediate display and can assert event replacement deterministically.
- testConcurrentOperations: pass minutesBeforeMeeting: 15 in concurrent overlayTask to ensure immediate visibility for events[0] (+10min).

Verification:
- swift test --filter 'SystemIntegrationTests/(testOverlappingEventsHandling|testConcurrentOperations|testCompleteEventSchedulingFlow)' passed.
- swift test --filter SystemIntegrationTests passed all 12 tests.
