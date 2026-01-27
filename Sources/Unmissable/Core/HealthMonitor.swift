import Foundation
import OSLog

@MainActor
final class HealthMonitor: ObservableObject {
  private let logger = Logger(subsystem: "com.unmissable.app", category: "HealthMonitor")

  @Published var healthStatus: HealthStatus = .healthy
  @Published var metrics: HealthMetrics = HealthMetrics()

  private var healthCheckTask: Task<Void, Never>?
  private let healthCheckInterval: TimeInterval = 60.0  // Check every minute
  private let memoryWarningThresholdMB: Double = 200.0  // Warn if app uses more than 200 MB

  // Dependencies to monitor
  private weak var calendarService: CalendarService?
  private weak var syncManager: SyncManager?
  private weak var overlayManager: OverlayManager?

  init() {
    startHealthMonitoring()
  }

  deinit {
    healthCheckTask?.cancel()
  }

  func setup(
    calendarService: CalendarService, syncManager: SyncManager, overlayManager: OverlayManager
  ) {
    self.calendarService = calendarService
    self.syncManager = syncManager
    self.overlayManager = overlayManager
  }

  private func startHealthMonitoring() {
    logger.info("Starting health monitoring")

    healthCheckTask = Task { @MainActor in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(Int(healthCheckInterval)))
          if !Task.isCancelled {
            await performHealthCheck()
          }
        } catch {
          // Task was cancelled, exit the loop
          break
        }
      }
    }
  }

  private func stopHealthMonitoring() {
    healthCheckTask?.cancel()
    healthCheckTask = nil
  }

  private func performHealthCheck() async {
    logger.debug("Performing health check")

    var issues: [HealthIssue] = []

    // Check calendar service health
    if let calendarService = calendarService {
      issues.append(contentsOf: checkCalendarServiceHealth(calendarService))
    }

    // Check sync manager health
    if let syncManager = syncManager {
      issues.append(contentsOf: checkSyncManagerHealth(syncManager))
    }

    // Check overlay manager health
    if let overlayManager = overlayManager {
      issues.append(contentsOf: checkOverlayManagerHealth(overlayManager))
    }

    // Check system resources
    issues.append(contentsOf: checkSystemHealth())

    // Update health status
    updateHealthStatus(issues: issues)
    updateMetrics()
  }

  private func checkCalendarServiceHealth(_ service: CalendarService) -> [HealthIssue] {
    var issues: [HealthIssue] = []

    if !service.isConnected {
      issues.append(
        HealthIssue(
          severity: .warning,
          component: "Calendar Service",
          message: "Not connected to Google Calendar",
          suggestion: "Check calendar connection in preferences"
        ))
    }

    return issues
  }

  private func checkSyncManagerHealth(_ syncManager: SyncManager) -> [HealthIssue] {
    var issues: [HealthIssue] = []

    if !syncManager.isOnline {
      issues.append(
        HealthIssue(
          severity: .warning,
          component: "Network",
          message: "Device is offline",
          suggestion: "Check internet connection"
        ))
    }

    if syncManager.retryCount > 3 {
      issues.append(
        HealthIssue(
          severity: .error,
          component: "Sync Manager",
          message: "Multiple sync failures (\(syncManager.retryCount) retries)",
          suggestion: "Check network and calendar permissions"
        ))
    }

    if let lastSync = syncManager.lastSyncTime,
      Date().timeIntervalSince(lastSync) > 3600
    {  // More than 1 hour
      issues.append(
        HealthIssue(
          severity: .warning,
          component: "Sync Manager",
          message: "Last sync was over 1 hour ago",
          suggestion: "Try manual sync or check network connection"
        ))
    }

    return issues
  }

  private func checkOverlayManagerHealth(_ overlayManager: OverlayManager) -> [HealthIssue] {
    var issues: [HealthIssue] = []

    // Check if overlay has been stuck visible for too long
    if overlayManager.isOverlayVisible,
      let activeEvent = overlayManager.activeEvent,
      Date().timeIntervalSince(activeEvent.endDate) > 1800
    {  // 30 minutes past end
      issues.append(
        HealthIssue(
          severity: .error,
          component: "Overlay Manager",
          message: "Overlay stuck visible for meeting that ended 30+ minutes ago",
          suggestion: "Restart the application if overlay won't dismiss"
        ))
    }

    return issues
  }

  private func checkSystemHealth() -> [HealthIssue] {
    var issues: [HealthIssue] = []

    // Check memory usage
    let memoryUsage = getMemoryUsage()
    let memoryThresholdBytes = Int(memoryWarningThresholdMB * 1024 * 1024)
    if memoryUsage > memoryThresholdBytes {
      issues.append(
        HealthIssue(
          severity: .warning,
          component: "System Resources",
          message: "High memory usage: \(memoryUsage / 1024 / 1024) MB",
          suggestion: "Consider restarting the application"
        ))
    }

    return issues
  }

  private func updateHealthStatus(issues: [HealthIssue]) {
    let criticalIssues = issues.filter { $0.severity == .error }
    let warnings = issues.filter { $0.severity == .warning }

    if !criticalIssues.isEmpty {
      healthStatus = .critical(issues: criticalIssues)
    } else if !warnings.isEmpty {
      healthStatus = .degraded(issues: warnings)
    } else {
      healthStatus = .healthy
    }
  }

  private func updateMetrics() {
    metrics.lastHealthCheck = Date()
    metrics.memoryUsageMB = Double(getMemoryUsage()) / 1024.0 / 1024.0
    metrics.uptime = ProcessInfo.processInfo.systemUptime
  }

  private func getMemoryUsage() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        task_info(
          mach_task_self_,
          task_flavor_t(MACH_TASK_BASIC_INFO),
          $0,
          &count)
      }
    }

    if kerr == KERN_SUCCESS {
      return Int(info.resident_size)
    } else {
      return 0
    }
  }

  func getHealthSummary() -> String {
    switch healthStatus {
    case .healthy:
      return "All systems operational"
    case .degraded(let issues):
      return "\(issues.count) warning\(issues.count == 1 ? "" : "s")"
    case .critical(let issues):
      return "\(issues.count) critical issue\(issues.count == 1 ? "" : "s")"
    }
  }
}

enum HealthStatus: Equatable {
  case healthy
  case degraded(issues: [HealthIssue])
  case critical(issues: [HealthIssue])

  var isHealthy: Bool {
    if case .healthy = self {
      return true
    }
    return false
  }
}

struct HealthIssue: Identifiable, Equatable {
  let id = UUID()
  let severity: Severity
  let component: String
  let message: String
  let suggestion: String

  enum Severity: String, CaseIterable {
    case warning = "warning"
    case error = "error"
  }
}

struct HealthMetrics {
  var lastHealthCheck: Date?
  var memoryUsageMB: Double = 0.0
  var uptime: TimeInterval = 0.0
}
