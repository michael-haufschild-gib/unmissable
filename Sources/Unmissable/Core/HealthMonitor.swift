import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class HealthMonitor {
    private let logger = Logger(category: "HealthMonitor")

    var healthStatus: HealthStatus = .healthy
    var metrics = HealthMetrics()

    @ObservationIgnored
    private var healthCheckTask: Task<Void, Never>?
    @ObservationIgnored
    private let memoryWarningThresholdMB: Double = 200.0 // Warn if app uses more than 200 MB

    /// Health check interval when all systems are healthy (5 minutes).
    private static let healthyCheckInterval: TimeInterval = 300.0
    /// Health check interval when issues are detected (1 minute).
    private static let degradedCheckInterval: TimeInterval = 60.0

    /// Retry count above which sync failures are flagged as critical.
    private static let syncRetryWarningThreshold = 3
    /// Seconds since last sync before a "stale sync" warning is raised.
    private static let staleSyncThresholdSeconds: TimeInterval = 3600
    /// Seconds an overlay may remain visible past meeting end before being considered stuck.
    private static let stuckOverlayThresholdSeconds: TimeInterval = 1800
    /// Bytes per kilobyte, used for memory unit conversion.
    private static let bytesPerKB = 1024
    /// Kilobytes per megabyte, used for memory unit conversion.
    private static let kbPerMB = 1024
    /// Size of `integer_t` in bytes, used to compute `task_info` count parameter.
    private static let integerTSize: mach_msg_type_number_t = 4
    /// Size of `mach_task_basic_info` in units of `integer_t`, for the `task_info` call.
    private static let machInfoCount =
        mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / integerTSize

    // Dependencies to monitor
    private weak var calendarService: CalendarService?
    private weak var overlayManager: (any OverlayManaging)?

    /// Registry key for sleep/wake callbacks.
    private static let sleepKey = "HealthMonitor"

    init(
        calendarService: CalendarService? = nil,
        overlayManager: (any OverlayManaging)? = nil,
        sleepObserver: SystemSleepObserver? = nil,
        startImmediately: Bool = true,
    ) {
        self.calendarService = calendarService
        self.overlayManager = overlayManager
        if startImmediately {
            startHealthMonitoring()
        }
        setupSleepObserver(sleepObserver)
    }

    deinit {
        healthCheckTask?.cancel()
    }

    private func setupSleepObserver(_ sleepObserver: SystemSleepObserver?) {
        guard let sleepObserver else { return }
        sleepObserver.register(
            key: Self.sleepKey,
            onSleep: { [weak self] in
                self?.stopHealthMonitoring()
            },
            onWake: { [weak self] in
                self?.startHealthMonitoring()
            },
        )
    }

    func setup(
        calendarService: CalendarService, overlayManager: any OverlayManaging,
    ) {
        self.calendarService = calendarService
        self.overlayManager = overlayManager
        performHealthCheck()
    }

    /// Returns the appropriate check interval based on current health status.
    /// Healthy systems are checked infrequently (5 min); degraded/critical systems
    /// are checked every minute to track resolution.
    private var currentCheckInterval: TimeInterval {
        healthStatus.isHealthy ? Self.healthyCheckInterval : Self.degradedCheckInterval
    }

    private func startHealthMonitoring() {
        logger.info("Starting health monitoring")

        healthCheckTask = Task { @MainActor in
            // Perform initial health check immediately
            performHealthCheck()

            while !Task.isCancelled {
                do {
                    let interval = currentCheckInterval
                    try await Task.sleep(for: .seconds(Int(interval)))
                    if !Task.isCancelled {
                        performHealthCheck()
                    }
                } catch {
                    break
                }
            }
        }
    }

    func stopHealthMonitoring() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }

    private func performHealthCheck() {
        logger.debug("Performing health check")

        var issues: [HealthIssue] = []

        // Check calendar service health
        if let calendarService {
            issues.append(contentsOf: checkCalendarServiceHealth(calendarService))
        }

        // Check sync manager health
        if let syncManager = calendarService?.primarySync {
            issues.append(contentsOf: checkSyncManagerHealth(syncManager))
        }

        // Check overlay manager health
        if let overlayManager {
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
                    message: "No calendar provider connected",
                    suggestion: "Check calendar connection in preferences",
                ),
            )
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
                    suggestion: "Check internet connection",
                ),
            )
        }

        if syncManager.retryCount > Self.syncRetryWarningThreshold {
            issues.append(
                HealthIssue(
                    severity: .error,
                    component: "Sync Manager",
                    message: "Multiple sync failures (\(syncManager.retryCount) retries)",
                    suggestion: "Check network and calendar permissions",
                ),
            )
        }

        if let lastSync = syncManager.lastSyncTime,
           Date().timeIntervalSince(lastSync) > Self.staleSyncThresholdSeconds
        { // More than 1 hour
            issues.append(
                HealthIssue(
                    severity: .warning,
                    component: "Sync Manager",
                    message: "Last sync was over 1 hour ago",
                    suggestion: "Try manual sync or check network connection",
                ),
            )
        }

        return issues
    }

    private func checkOverlayManagerHealth(_ overlayManager: any OverlayManaging) -> [HealthIssue] {
        var issues: [HealthIssue] = []

        // Report overlay stuck visible for 30+ minutes past meeting end
        if overlayManager.isOverlayVisible,
           let activeEvent = overlayManager.activeEvent,
           Date().timeIntervalSince(activeEvent.endDate) > Self.stuckOverlayThresholdSeconds
        {
            logger.warning(
                "Stuck overlay detected for event \(PrivacyUtils.redactedEventId(activeEvent.id)) — meeting ended 30+ minutes ago",
            )
            issues.append(
                HealthIssue(
                    severity: .warning,
                    component: "Overlay Manager",
                    message: "Overlay stuck for meeting that ended 30+ minutes ago",
                    suggestion: "Dismiss the overlay manually or restart the app",
                ),
            )
        }

        return issues
    }

    private func checkSystemHealth() -> [HealthIssue] {
        var issues: [HealthIssue] = []

        // Check memory usage
        let memoryUsage = getMemoryUsage()
        let memoryThresholdBytes = Int(memoryWarningThresholdMB) * Self.bytesPerKB * Self.kbPerMB
        if memoryUsage > memoryThresholdBytes {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    component: "System Resources",
                    message: "High memory usage: \(memoryUsage / Self.bytesPerKB / Self.kbPerMB) MB",
                    suggestion: "Consider restarting the application",
                ),
            )
        }

        return issues
    }

    private func updateHealthStatus(issues: [HealthIssue]) {
        let criticalIssues = issues.filter { $0.severity == .error }
        let warnings = issues.filter { $0.severity == .warning }

        let previousStatus = healthStatus

        if !criticalIssues.isEmpty {
            healthStatus = .critical(issues: criticalIssues)
        } else if !warnings.isEmpty {
            healthStatus = .degraded(issues: warnings)
        } else {
            healthStatus = .healthy
        }

        // Only log on state transitions to avoid timer spam
        if healthStatus != previousStatus {
            let issueDescriptions = issues.map { "\($0.component):\($0.message)" }
            AppDiagnostics.record(component: "HealthMonitor", phase: "statusChanged") {
                [
                    "from": "\(previousStatus.isHealthy ? "healthy" : "degraded/critical")",
                    "to": "\(self.healthStatus.isHealthy ? "healthy" : "degraded/critical")",
                    "issues": issueDescriptions.joined(separator: "; "),
                ]
            }
        }
    }

    private func updateMetrics() {
        metrics.lastHealthCheck = Date()
        metrics.memoryUsageMB = Double(getMemoryUsage()) / Double(Self.bytesPerKB) / Double(Self.kbPerMB)
        metrics.uptime = ProcessInfo.processInfo.systemUptime
    }

    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = Self.machInfoCount

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count,
                )
            }
        }

        if kerr == KERN_SUCCESS {
            return Int(info.resident_size)
        }
        return 0
    }

    func getHealthSummary() -> String {
        switch healthStatus {
        case .healthy:
            return "All systems operational"
        case let .degraded(issues):
            return "\(issues.count) warning\(issues.count == 1 ? "" : "s")"
        case let .critical(issues):
            let critCount = issues.count { $0.severity == .error }
            let warnCount = issues.count { $0.severity == .warning }
            if warnCount > 0 {
                return "\(critCount) critical, \(warnCount) warning\(warnCount == 1 ? "" : "s")"
            }
            return "\(critCount) critical issue\(critCount == 1 ? "" : "s")"
        }
    }
}

@MainActor
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

@MainActor
struct HealthIssue: Identifiable, Equatable {
    let id = UUID()
    let severity: Severity
    let component: String
    let message: String
    let suggestion: String

    enum Severity: String, CaseIterable {
        case warning
        case error
    }

    /// Value equality ignores `id` (UUID) so identical issues deduplicate
    /// regardless of when they were created. `id` is only for Identifiable.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.severity == rhs.severity
            && lhs.component == rhs.component
            && lhs.message == rhs.message
            && lhs.suggestion == rhs.suggestion
    }
}

@MainActor
struct HealthMetrics {
    var lastHealthCheck: Date?
    var memoryUsageMB: Double = 0.0
    var uptime: TimeInterval = 0.0
}
