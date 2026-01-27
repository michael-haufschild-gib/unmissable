import Foundation
import OSLog

/// PRODUCTION OVERLAY TEST
/// This will test the exact scenario described by the user
/// Run this with: swift run --target UnmissableTest
class ProductionOverlayTest {
  private static let logger = Logger(subsystem: "com.unmissable.app", category: "ProductionOverlayTest")

  static func main() async {
    logger.info("🚨 PRODUCTION OVERLAY DEADLOCK TEST")
    logger.info("Simulating exact user scenario: scheduled alert triggering overlay")

    // Create production-identical components
    let preferencesManager = PreferencesManager()
    let overlayManager = OverlayManager(preferencesManager: preferencesManager)
    let eventScheduler = EventScheduler(preferencesManager: preferencesManager)

    // Connect exactly as in production
    overlayManager.setEventScheduler(eventScheduler)

    logger.info("📅 Creating test event that triggers in 3 seconds...")

    // Create event that should trigger an overlay in 3 seconds
    let futureTime = Date().addingTimeInterval(3)
    let testEvent = Event(
      id: "production-test",
      title: "Production Deadlock Test",
      startDate: futureTime.addingTimeInterval(300),  // Event starts 5 minutes after trigger
      endDate: futureTime.addingTimeInterval(3900),  // 1 hour long
      organizer: "test@example.com",
      calendarId: "test-calendar"
    )

    logger.info("🎯 Event created. Starting EventScheduler monitoring...")

    // Start the exact same process as production
    await eventScheduler.startScheduling(events: [testEvent], overlayManager: overlayManager)

    logger.info("⏰ Waiting for scheduled alert to trigger...")
    logger.info("   User reported: sound plays but overlay doesn't open, app freezes")

    let startTime = Date()
    var overlayAppeared = false

    // Monitor for 10 seconds
    while Date().timeIntervalSince(startTime) < 10 {
      try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second checks

      let elapsed = Date().timeIntervalSince(startTime)

      if elapsed >= 3.5 && !overlayAppeared {
        let isVisible = overlayManager.isOverlayVisible
        if isVisible {
          overlayAppeared = true
          logger.info("✅ SUCCESS at \(elapsed)s: Overlay appeared!")
          logger.info("🎉 DEADLOCK FIXED: Scheduled alert successfully triggered overlay")
          break
        }
      }

      if elapsed >= 8 && !overlayAppeared {
        logger.error("❌ DEADLOCK STILL EXISTS at \(elapsed)s: No overlay despite scheduled alert")
        logger.error("   This matches the user's exact report")
        break
      }
    }

    let totalTime = Date().timeIntervalSince(startTime)
    logger.info("📊 Test completed in \(totalTime) seconds")

    if overlayAppeared {
      logger.info("🎯 CRITICAL FIX VALIDATED: User's deadlock issue is resolved")
      overlayManager.hideOverlay()
    } else {
      logger.warning("⚠️ DEADLOCK PERSISTS: Further investigation needed")
    }

    eventScheduler.stopScheduling()
    logger.info("🏁 Production test complete")
  }
}

// Run the test
await ProductionOverlayTest.main()
