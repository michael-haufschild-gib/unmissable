import AppKit
import Foundation
import OSLog
@testable import Unmissable
import XCTest

/// COMPREHENSIVE END-TO-END DEADLOCK PREVENTION TEST SUITE
/// This test consolidates all deadlock scenarios into a single comprehensive suite
/// Focus: Prevent deadlocks in production by testing real-world scenarios
@MainActor
class EndToEndDeadlockPreventionTests: XCTestCase {
    private let logger = Logger(subsystem: "com.unmissable.test", category: "E2EDeadlockPrevention")

    // MARK: - Test Environment Setup

    override func setUp() async throws {
        try await super.setUp()
        logger.info("🧪 Setting up End-to-End Deadlock Prevention Test Suite")
    }

    override func tearDown() async throws {
        logger.info("🧹 Cleaning up End-to-End Deadlock Prevention Test Suite")
        try await super.tearDown()
    }

    // MARK: - CRITICAL: Timer + Window Server Deadlock Prevention

    func testTimerWindowServerDeadlockPrevention() async throws {
        logger.info("🚨 CRITICAL E2E: Timer + Window Server deadlock prevention")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)

        // Only test with isTestMode: true to avoid blocking screen with real windows
        for isTestMode in [true] {
            logger.info("🔄 Testing with isTestMode: \(isTestMode)")

            let overlayManager = OverlayManager(
                preferencesManager: preferencesManager,
                focusModeManager: focusModeManager,
                isTestMode: isTestMode
            )

            let testEvent = TestUtilities.createTestEvent(
                id: "timer-window-deadlock-test",
                title: "Timer Window Deadlock Test",
                startDate: Date().addingTimeInterval(300)
            )

            // SCENARIO 1: Show overlay and immediately dismiss (worst case)
            logger.info("📊 Scenario 1: Immediate show/dismiss cycle")
            let startTime = Date()

            overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
            XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

            // Immediately dismiss without waiting (simulates rapid user interaction)
            overlayManager.hideOverlay()
            XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden")

            let cycleTime = Date().timeIntervalSince(startTime)
            XCTAssertLessThan(cycleTime, 2.0, "Show/hide cycle should complete quickly")

            // SCENARIO 2: Show, wait for timer, then dismiss during timer execution
            logger.info("📊 Scenario 2: Dismiss during timer execution")

            overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
            XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

            // Wait for timer to be established and running
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Dismiss while timer is active
            let dismissStart = Date()
            overlayManager.hideOverlay()
            let dismissTime = Date().timeIntervalSince(dismissStart)

            XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden")
            XCTAssertLessThan(dismissTime, 1.0, "Dismiss during timer should complete quickly")

            // SCENARIO 3: Rapid show/hide cycles (stress test)
            logger.info("📊 Scenario 3: Rapid cycles stress test")

            for cycle in 1 ... 5 {
                let cycleStart = Date()

                overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
                XCTAssertTrue(overlayManager.isOverlayVisible, "Cycle \(cycle): Overlay should be visible")

                overlayManager.hideOverlay()
                XCTAssertFalse(overlayManager.isOverlayVisible, "Cycle \(cycle): Overlay should be hidden")

                let cycleTime = Date().timeIntervalSince(cycleStart)
                XCTAssertLessThan(cycleTime, 1.0, "Cycle \(cycle) should complete quickly")
            }

            logger.info("✅ All scenarios passed for isTestMode: \(isTestMode)")
        }

        logger.info("✅ Timer + Window Server deadlock prevention test completed successfully")
    }

    // MARK: - CRITICAL: SwiftUI Button Callback Deadlock Prevention

    func testSwiftUIButtonCallbackDeadlockPrevention() async throws {
        logger.info("🚨 CRITICAL E2E: SwiftUI button callback deadlock prevention")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )

        let testEvent = TestUtilities.createTestEvent(
            id: "button-callback-test",
            title: "Button Callback Test",
            startDate: Date().addingTimeInterval(300)
        )

        // Show overlay
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

        // Wait for timer to be established
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Simulate exact SwiftUI button callback pattern from OverlayManager
        logger.info("🔘 Simulating SwiftUI dismiss button callback...")

        let callbackStart = Date()
        var callbackCompleted = false

        // This is the exact pattern used in OverlayManager.createOverlayWindows
        let dismissCallback = { [weak overlayManager] in
            Task { @MainActor in
                overlayManager?.hideOverlay()
                callbackCompleted = true
            }
        }

        // Execute the callback
        _ = dismissCallback()

        // Wait for completion with timeout
        var timeoutCounter = 0
        while !callbackCompleted, timeoutCounter < 30 { // 3 second timeout
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            timeoutCounter += 1
        }

        let callbackTime = Date().timeIntervalSince(callbackStart)

        XCTAssertTrue(callbackCompleted, "Button callback should complete")
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after callback")
        XCTAssertLessThan(callbackTime, 2.0, "Button callback should complete quickly")

        logger.info("✅ SwiftUI button callback deadlock prevention test completed successfully")
    }

    // MARK: - CRITICAL: Production Snooze Workflow End-to-End

    func testProductionSnoozeWorkflowE2E() {
        logger.info("🚨 CRITICAL E2E: Production snooze workflow deadlock prevention")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )
        let eventScheduler = EventScheduler(preferencesManager: preferencesManager)
        overlayManager.setEventScheduler(eventScheduler)

        let testEvent = TestUtilities.createTestEvent(
            id: "snooze-workflow-test",
            title: "Snooze Workflow Test",
            startDate: Date().addingTimeInterval(120) // 2 minutes from now
        )

        // STEP 1: Initial overlay display
        logger.info("📊 Step 1: Initial overlay display")
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 2)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Initial overlay should be visible")

        // STEP 2: Snooze for 1 minute
        logger.info("📊 Step 2: Snooze operation")
        let snoozeStart = Date()
        overlayManager.snoozeOverlay(for: 1)

        // Overlay should be hidden after snooze
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")

        let snoozeTime = Date().timeIntervalSince(snoozeStart)
        XCTAssertLessThan(snoozeTime, 1.0, "Snooze operation should complete quickly")

        // STEP 3: Wait for snooze to re-trigger (simulate, don't wait real time)
        logger.info("📊 Step 3: Simulating snooze re-trigger")

        // Simulate snooze alert firing
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 0, fromSnooze: true)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Snoozed overlay should be visible")

        // STEP 4: Dismiss snoozed overlay
        logger.info("📊 Step 4: Dismiss snoozed overlay")
        let dismissStart = Date()
        overlayManager.hideOverlay()

        XCTAssertFalse(overlayManager.isOverlayVisible, "Snoozed overlay should be hidden")

        let dismissTime = Date().timeIntervalSince(dismissStart)
        XCTAssertLessThan(dismissTime, 1.0, "Snoozed overlay dismiss should complete quickly")

        logger.info("✅ Production snooze workflow E2E test completed successfully")
    }

    // MARK: - CRITICAL: EventScheduler Integration End-to-End

    func testEventSchedulerIntegrationE2E() async throws {
        logger.info("🚨 CRITICAL E2E: EventScheduler integration deadlock prevention")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )
        let eventScheduler = EventScheduler(preferencesManager: preferencesManager)
        overlayManager.setEventScheduler(eventScheduler)

        // Create events with different timing patterns
        let events = [
            TestUtilities.createTestEvent(
                id: "immediate-event",
                title: "Immediate Event",
                startDate: Date().addingTimeInterval(-30) // Started 30 seconds ago
            ),
            TestUtilities.createTestEvent(
                id: "upcoming-event",
                title: "Upcoming Event",
                startDate: Date().addingTimeInterval(300) // 5 minutes from now
            ),
            TestUtilities.createTestEvent(
                id: "future-event",
                title: "Future Event",
                startDate: Date().addingTimeInterval(3600) // 1 hour from now
            ),
        ]

        logger.info("📊 Starting EventScheduler with \(events.count) events")

        // Start scheduling
        let schedulingStart = Date()
        await eventScheduler.startScheduling(events: events, overlayManager: overlayManager)
        let schedulingTime = Date().timeIntervalSince(schedulingStart)

        XCTAssertLessThan(schedulingTime, 2.0, "Event scheduling should complete quickly")

        // Test immediate overlay trigger for past event
        logger.info("📊 Testing immediate overlay trigger")
        overlayManager.showOverlay(for: events[0], minutesBeforeMeeting: 5, fromSnooze: false)

        // Should trigger immediately since event is in the past
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // The overlay might or might not be visible depending on auto-hide logic for past events
        // This is acceptable - the key is no deadlock occurred

        // Test future overlay scheduling
        logger.info("📊 Testing future overlay scheduling")
        overlayManager
            .showOverlay(
                for: events[1],
                minutesBeforeMeeting: 15,
                fromSnooze: false
            ) // 15 minutes before 10-minute future event

        // Should not trigger immediately (15 minutes before 10-minute future event = won't trigger)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        // Note: The actual visibility depends on timing logic, but key is no deadlock occurred

        // Stop scheduling
        let stopStart = Date()
        eventScheduler.stopScheduling()
        let stopTime = Date().timeIntervalSince(stopStart)

        XCTAssertLessThan(stopTime, 1.0, "Event scheduling stop should complete quickly")

        logger.info("✅ EventScheduler integration E2E test completed successfully")
    }

    // MARK: - CRITICAL: Concurrent Operations Stress Test

    func testConcurrentOperationsStressE2E() async {
        logger.info("🚨 CRITICAL E2E: Concurrent operations stress test")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )

        let events = (1 ... 10).map { index in
            TestUtilities.createTestEvent(
                id: "stress-event-\(index)",
                title: "Stress Event \(index)",
                startDate: Date().addingTimeInterval(Double(index * 60))
            )
        }

        logger.info("📊 Starting operations stress test with \(events.count) events")

        // Test sequential show/hide operations (TaskGroup with @MainActor has compiler issues in Swift 6)
        for (index, event) in events.enumerated() {
            let operationStart = Date()

            // Show overlay
            overlayManager.showOverlay(for: event, minutesBeforeMeeting: 5)

            // Brief delay to let timer establish
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            // Hide overlay
            overlayManager.hideOverlay()

            let operationTime = Date().timeIntervalSince(operationStart)
            XCTAssertLessThan(operationTime, 2.0, "Operation \(index) should complete quickly")

            logger.info("✅ Operation \(index + 1) completed in \(operationTime)s")
        }

        // Ensure final state is clean
        XCTAssertFalse(
            overlayManager.isOverlayVisible, "No overlay should be visible after stress test"
        )

        logger.info("✅ Concurrent operations stress test completed successfully")
    }

    // MARK: - CRITICAL: Memory and Resource Cleanup

    func testMemoryAndResourceCleanupE2E() async throws {
        logger.info("🚨 CRITICAL E2E: Memory and resource cleanup verification")

        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)

        // Create and destroy multiple overlay managers to test cleanup
        for iteration in 1 ... 5 {
            logger.info("📊 Cleanup iteration \(iteration)")

            let overlayManager = OverlayManager(
                preferencesManager: preferencesManager,
                focusModeManager: focusModeManager,
                isTestMode: true
            )

            let testEvent = TestUtilities.createTestEvent(
                id: "cleanup-test-\(iteration)",
                title: "Cleanup Test \(iteration)",
                startDate: Date().addingTimeInterval(300)
            )

            // Create and destroy overlays multiple times
            for cycle in 1 ... 3 {
                overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
                XCTAssertTrue(
                    overlayManager.isOverlayVisible, "Overlay should be visible in cycle \(cycle)"
                )

                // Let timer run briefly
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

                overlayManager.hideOverlay()
                XCTAssertFalse(
                    overlayManager.isOverlayVisible, "Overlay should be hidden in cycle \(cycle)"
                )
            }

            // Explicit cleanup - overlayManager will be deallocated at end of scope
            overlayManager.hideOverlay()

            logger.info("✅ Cleanup iteration \(iteration) completed")
        }

        logger.info("✅ Memory and resource cleanup E2E test completed successfully")
    }

    // MARK: - COMPREHENSIVE: All Scenarios Combined

    func testAllDeadlockScenariosComprehensiveE2E() async throws {
        logger.info("🚨 COMPREHENSIVE E2E: All deadlock scenarios combined")

        let startTime = Date()
        let preferencesManager = PreferencesManager()
        let focusModeManager = FocusModeManager(preferencesManager: preferencesManager)
        let overlayManager = OverlayManager(
            preferencesManager: preferencesManager,
            focusModeManager: focusModeManager,
            isTestMode: true
        )
        let eventScheduler = EventScheduler(preferencesManager: preferencesManager)
        overlayManager.setEventScheduler(eventScheduler)

        let testEvent = TestUtilities.createTestEvent(
            id: "comprehensive-test",
            title: "Comprehensive Deadlock Prevention Test",
            startDate: Date().addingTimeInterval(300)
        )

        // Combined scenario: All operations in rapid succession
        logger.info("📊 Comprehensive scenario: All operations combined")

        // 1. Start scheduling
        await eventScheduler.startScheduling(events: [testEvent], overlayManager: overlayManager)

        // 2. Show overlay
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Overlay should be visible")

        // 3. Wait for timer
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // 4. Snooze
        overlayManager.snoozeOverlay(for: 1)
        XCTAssertFalse(overlayManager.isOverlayVisible, "Overlay should be hidden after snooze")

        // 5. Show snoozed overlay
        overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 0, fromSnooze: true)
        XCTAssertTrue(overlayManager.isOverlayVisible, "Snoozed overlay should be visible")

        // 6. Rapid hide/show cycles
        for _ in 1 ... 3 {
            overlayManager.hideOverlay()
            overlayManager.showOverlay(for: testEvent, minutesBeforeMeeting: 5)
        }

        // 7. Final cleanup
        overlayManager.hideOverlay()
        eventScheduler.stopScheduling()

        XCTAssertFalse(
            overlayManager.isOverlayVisible, "No overlay should be visible after comprehensive test"
        )

        let totalTime = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(totalTime, 10.0, "Comprehensive test should complete within 10 seconds")

        logger.info("✅ Comprehensive deadlock prevention test completed in \(totalTime)s")
    }
}
