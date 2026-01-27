import Foundation
import OSLog

/// Thread-safe overlay trigger that handles timing and scheduling without complex async chains
/// Eliminates deadlocks by using simple, direct dispatch patterns
@MainActor
final class OverlayTrigger: ObservableObject {
  private let logger = Logger(subsystem: "com.unmissable.app", category: "OverlayTrigger")

  @Published var scheduledCount = 0

  /// Maps event IDs to their scheduled tasks for targeted cancellation
  private var scheduledTasks: [String: Task<Void, Never>] = [:]

  deinit {
    // Clean up all tasks synchronously in deinit
    for (_, task) in scheduledTasks {
      task.cancel()
    }
  }

  /// Schedule an overlay to display at a specific future time
  /// Uses simple, direct timer dispatch to eliminate async chain complexity
  func scheduleOverlay(
    for event: Event,
    at triggerTime: Date,
    handler: @escaping () -> Void
  ) {
    let timeInterval = triggerTime.timeIntervalSinceNow

    guard timeInterval > 0 else {
      logger.warning("Cannot schedule overlay for past time: \(triggerTime)")
      return
    }

    // Cancel any existing task for this event before scheduling new one
    if let existingTask = scheduledTasks[event.id] {
      existingTask.cancel()
      logger.info("Cancelled existing overlay for '\(event.title)' before rescheduling")
    }

    logger.info("Scheduling overlay for '\(event.title)' in \(timeInterval) seconds")

    // Use async task instead of timer for better modern Swift patterns
    let eventId = event.id
    let task = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .seconds(timeInterval))
        if !Task.isCancelled {
          handler()
          // Remove completed task from dictionary
          self?.scheduledTasks.removeValue(forKey: eventId)
          self?.scheduledCount = self?.scheduledTasks.count ?? 0
        }
      } catch is CancellationError {
        // Task was cancelled - expected
      } catch {
        self?.logger.error("Unexpected error in scheduled overlay: \(error.localizedDescription)")
      }
    }

    scheduledTasks[event.id] = task
    scheduledCount = scheduledTasks.count

    logger.info("Overlay scheduled. Total scheduled: \(self.scheduledCount)")
  }

  /// Trigger overlay immediately for alerts that should fire now
  func triggerImmediately(
    for event: Event,
    handler: @escaping () -> Void
  ) {
    logger.info("Triggering immediate overlay for: \(event.title)")

    // Execute handler directly - no async dispatch needed
    handler()
  }

  /// Cancel all scheduled overlays
  func cancelAllScheduled() {
    logger.info("Cancelling \(self.scheduledTasks.count) scheduled tasks")

    for (_, task) in scheduledTasks {
      task.cancel()
    }
    scheduledTasks.removeAll()
    scheduledCount = 0
  }

  /// Cancel overlay for a specific event
  func cancelScheduled(for eventId: String) {
    if let task = scheduledTasks[eventId] {
      task.cancel()
      scheduledTasks.removeValue(forKey: eventId)
      scheduledCount = scheduledTasks.count
      logger.info("Cancelled scheduled overlay for event: \(eventId)")
    } else {
      logger.debug("No scheduled overlay found for event: \(eventId)")
    }
  }
}
