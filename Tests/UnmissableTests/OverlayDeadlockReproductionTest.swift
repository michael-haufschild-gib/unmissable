import Foundation
@testable import Unmissable
import XCTest

/// Test to reproduce the actual overlay deadlock issue reported by user
@MainActor
class OverlayDeadlockReproductionTest: XCTestCase {
    func testOverlayDeadlockOnScheduledAlert() async throws {
        print("🧪 TESTING: Reproduce overlay deadlock when scheduled alert fires")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true // CRITICAL FIX: Prevent UI creation in tests
        )
        let eventScheduler = EventScheduler(preferencesManager: preferencesManager)

        // Connect EventScheduler to OverlayManager
        overlayManager.setEventScheduler(eventScheduler)

        // Create test event that should trigger in 2 seconds
        let futureTime = Date().addingTimeInterval(2)
        let testEvent = TestUtilities.createTestEvent(
            id: "deadlock-test",
            title: "Deadlock Test Event",
            startDate: futureTime
        )

        print("📅 Created test event starting at: \(futureTime)")

        // Schedule the event through EventScheduler (this simulates real usage)
        await eventScheduler.startScheduling(events: [testEvent], overlayManager: overlayManager)

        print("⏰ Event scheduled. Waiting for alert to trigger...")

        // Wait for the scheduled alert to fire (3 seconds should be enough)
        try await Task.sleep(nanoseconds: 3_000_000_000)

        print("🔍 Checking if overlay displayed...")

        // Check if overlay was successfully displayed
        let overlayVisible = overlayManager.isOverlayVisible
        print("Overlay visible: \(overlayVisible)")

        if !overlayVisible {
            print("❌ DEADLOCK REPRODUCED: Overlay did not display despite scheduled alert")
            print("   This matches user's report: 'sound plays but overlay is not opening'")
        } else {
            print("✅ Overlay displayed successfully - no deadlock detected")
        }

        // Clean up
        overlayManager.hideOverlay()
        eventScheduler.stopScheduling()
    }

    func testOverlayCreationDirectly() async throws {
        print("🧪 TESTING: Direct overlay creation to isolate deadlock")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true // CRITICAL FIX: Prevent UI creation in tests
        )

        let testEvent = TestUtilities.createTestEvent(
            title: "Direct Test Event",
            startDate: Date().addingTimeInterval(300)
        )

        print("🎯 Attempting direct overlay creation...")

        // Try to create overlay directly - this should reveal if deadlock is in overlay creation
        overlayManager.showOverlay(for: testEvent)

        // Give it a moment to process
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let overlayVisible = overlayManager.isOverlayVisible
        print("Direct overlay creation result: \(overlayVisible)")

        if !overlayVisible {
            print("❌ DEADLOCK IN DIRECT CREATION: Even direct overlay creation fails")
        } else {
            print("✅ Direct overlay creation works - issue is in scheduling/triggering")
        }

        overlayManager.hideOverlay()
    }
}
