import Foundation
@testable import Unmissable
import XCTest

/// Focused test to reproduce the specific deadlock scenario reported by user
@MainActor
class OverlayDeadlockSimpleTest: XCTestCase {
    func testDirectOverlayCreation() {
        print("🧪 TESTING: Direct overlay creation to see if it deadlocks")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true // CRITICAL FIX: Prevent UI creation in tests
        )

        let testEvent = TestUtilities.createTestEvent(
            title: "Test Event",
            startDate: Date().addingTimeInterval(300)
        )

        print("🎯 Attempting to create overlay...")

        let startTime = Date()

        // This is where the deadlock should occur according to user report
        overlayManager.showOverlay(for: testEvent)

        let endTime = Date()
        let timeElapsed = endTime.timeIntervalSince(startTime)

        print("⏱️ Overlay creation took \(timeElapsed) seconds")

        if timeElapsed > 5.0 {
            print("❌ POTENTIAL DEADLOCK: Overlay creation took too long (\(timeElapsed)s)")
        } else {
            print("✅ Overlay creation completed in reasonable time")
        }

        let isVisible = overlayManager.isOverlayVisible
        print("📊 Overlay visible: \(isVisible)")

        // Clean up
        overlayManager.hideOverlay()

        // The user reported "sound plays but overlay not opening"
        // If sound plays but overlay doesn't show, that's the bug
        if !isVisible {
            print("❌ BUG REPRODUCED: Overlay creation completed but overlay not visible")
            print("   This matches user report: overlay doesn't appear despite no crash")
        }
    }

    func testScheduledOverlayTrigger() async throws {
        print("🧪 TESTING: Scheduled overlay trigger (closer to real scenario)")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true // CRITICAL FIX: Prevent UI creation in tests
        )

        // Create event that should trigger immediately (past event)
        let pastEvent = TestUtilities.createTestEvent(
            title: "Past Event",
            startDate: Date().addingTimeInterval(-30) // 30 seconds ago
        )

        print("📅 Testing with past event to trigger immediate overlay")

        let startTime = Date()

        // Use scheduleOverlay which is closer to real usage
        overlayManager.showOverlay(for: pastEvent, minutesBeforeMeeting: 5, fromSnooze: false)

        // Wait a moment for any async processing
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let endTime = Date()
        let timeElapsed = endTime.timeIntervalSince(startTime)

        print("⏱️ Scheduled overlay processing took \(timeElapsed) seconds")

        let isVisible = overlayManager.isOverlayVisible
        print("📊 Overlay visible after scheduling: \(isVisible)")

        overlayManager.hideOverlay()
    }
}
