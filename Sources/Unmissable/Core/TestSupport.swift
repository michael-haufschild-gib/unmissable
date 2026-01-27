import Foundation
import OSLog

// MARK: - Test-Safe Implementations

/// Test-safe overlay manager that doesn't create actual UI elements
@MainActor
final class TestSafeOverlayManager: OverlayManaging {
  private let logger = Logger(subsystem: "com.unmissable.app", category: "TestSupport")

  @Published var activeEvent: Event?
  @Published var isOverlayVisible = false

  /// Computed time until meeting starts (negative if meeting has started)
  var timeUntilMeeting: TimeInterval {
    activeEvent?.startDate.timeIntervalSinceNow ?? 0
  }

  private weak var eventScheduler: EventScheduler?
  private let isTestEnvironment: Bool

  init(isTestEnvironment: Bool = false) {
    self.isTestEnvironment = isTestEnvironment
  }

  func showOverlay(for event: Event, minutesBeforeMeeting: Int = 5, fromSnooze: Bool = false) {
    logger.debug("🎬 TEST-SAFE SHOW: Overlay for \(event.title), fromSnooze: \(fromSnooze)")

    if isTestEnvironment {
      // In test environment, just set state without creating UI
      activeEvent = event
      isOverlayVisible = true
      logger.debug("✅ TEST-SAFE: Set overlay visible = true")
    } else {
      // In production, would create actual UI (but this class is for testing)
      activeEvent = event
      isOverlayVisible = true
    }
  }

  func hideOverlay() {
    logger.debug("🎬 TEST-SAFE HIDE: Overlay")
    activeEvent = nil
    isOverlayVisible = false
  }

  func snoozeOverlay(for minutes: Int) {
    guard let event = activeEvent else { return }
    logger.debug("⏰ TEST-SAFE SNOOZE: \(minutes) minutes for \(event.title)")
    hideOverlay()
    eventScheduler?.scheduleSnooze(for: event, minutes: minutes)
  }

  func setEventScheduler(_ scheduler: EventScheduler) {
    self.eventScheduler = scheduler
  }
}

// MARK: - Factory for Environment-Specific Implementations

enum OverlayManagerFactory {
  @MainActor
  static func create(
    preferencesManager: PreferencesManager,
    focusModeManager: FocusModeManager? = nil,
    isTestEnvironment: Bool = false
  ) -> any OverlayManaging {

    if isTestEnvironment {
      return TestSafeOverlayManager(isTestEnvironment: true)
    } else {
      return OverlayManager(
        preferencesManager: preferencesManager,
        focusModeManager: focusModeManager
      )
    }
  }
}
