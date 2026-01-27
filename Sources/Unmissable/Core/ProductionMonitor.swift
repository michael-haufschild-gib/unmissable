import Foundation
import OSLog

/// Production-ready error handling and monitoring system
@MainActor
final class ProductionMonitor: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "ProductionMonitor")

    @Published var systemHealth: SystemHealth = .healthy
    @Published var errorCount: Int = 0
    @Published var lastError: ProductionError?

    private var errorHistory: [ProductionError] = []
    private let maxErrorHistory = 100

    // Performance metrics
    @Published var averageOverlayResponseTime: TimeInterval = 0
    private var responseTimeHistory: [TimeInterval] = []
    private var monitoringTask: Task<Void, Never>?

    static let shared = ProductionMonitor()

    private init() {
        setupPerformanceMonitoring()
    }

    /// Log a production error with context
    func logError(_ error: ProductionError) {
        logger.error("🚨 PRODUCTION ERROR: \(error.description)")

        errorCount += 1
        lastError = error
        errorHistory.append(error)

        // Keep history manageable
        if errorHistory.count > maxErrorHistory {
            errorHistory.removeFirst(errorHistory.count - maxErrorHistory)
        }

        // Update system health based on error patterns
        updateSystemHealth()
    }

    /// Log successful overlay display with timing
    func logOverlaySuccess(responseTime: TimeInterval) {
        responseTimeHistory.append(responseTime)

        // Keep last 50 measurements for rolling average
        if responseTimeHistory.count > 50 {
            responseTimeHistory.removeFirst()
        }

        averageOverlayResponseTime =
            responseTimeHistory.reduce(0, +) / Double(responseTimeHistory.count)

        logger.info(
            "✅ OVERLAY SUCCESS: \(String(format: "%.1f", responseTime * 1000))ms (avg: \(String(format: "%.1f", averageOverlayResponseTime * 1000))ms)"
        )
    }

    /// Check system health status
    private func updateSystemHealth() {
        let recentErrors = errorHistory.suffix(10)
        let criticalErrorCount = recentErrors.filter { $0.severity == .critical }.count
        let errorRate = recentErrors.count

        if criticalErrorCount > 3 {
            systemHealth = .critical
        } else if errorRate > 7 {
            systemHealth = .degraded
        } else if errorRate > 3 {
            systemHealth = .warning
        } else {
            systemHealth = .healthy
        }

        logger.info("📊 SYSTEM HEALTH: \(systemHealth.rawValue) (recent errors: \(errorRate))")
    }

    /// Setup performance monitoring
    private func setupPerformanceMonitoring() {
        // Monitor for high memory usage
        monitoringTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                    if !Task.isCancelled {
                        checkSystemResources()
                    }
                } catch {
                    // Task was cancelled, exit the loop
                    break
                }
            }
        }
    }

    /// Check system resource usage
    private func checkSystemResources() {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if kerr == KERN_SUCCESS {
            let memoryMB = Double(memoryInfo.resident_size) / 1024.0 / 1024.0

            if memoryMB > 500 {
                logError(
                    ProductionError(
                        type: .performance,
                        severity: .warning,
                        message: "High memory usage: \(String(format: "%.1f", memoryMB))MB",
                        context: ["memory_mb": "\(memoryMB)"]
                    )
                )
            }

            logger.info("📊 MEMORY USAGE: \(String(format: "%.1f", memoryMB))MB")
        }
    }

    /// Get health summary for monitoring dashboards
    func getHealthSummary() -> HealthSummary {
        HealthSummary(
            systemHealth: systemHealth,
            totalErrors: errorCount,
            averageResponseTime: averageOverlayResponseTime,
            recentErrorCount: errorHistory.suffix(10).count,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    deinit {
        monitoringTask?.cancel()
    }
}

// MARK: - Supporting Types

enum SystemHealth: String, CaseIterable {
    case healthy
    case warning
    case degraded
    case critical

    var emoji: String {
        switch self {
        case .healthy: "✅"
        case .warning: "⚠️"
        case .degraded: "🟡"
        case .critical: "🚨"
        }
    }
}

struct ProductionError {
    let type: ErrorType
    let severity: ErrorSeverity
    let message: String
    let context: [String: String]
    let timestamp: Date

    init(type: ErrorType, severity: ErrorSeverity, message: String, context: [String: String] = [:]) {
        self.type = type
        self.severity = severity
        self.message = message
        self.context = context
        timestamp = Date()
    }

    var description: String {
        "[\(severity.rawValue.uppercased())] \(type.rawValue): \(message)"
    }
}

enum ErrorType: String {
    case deadlock
    case ui
    case performance
    case network
    case calendar
    case system
}

enum ErrorSeverity: String {
    case info
    case warning
    case error
    case critical
}

struct HealthSummary {
    let systemHealth: SystemHealth
    let totalErrors: Int
    let averageResponseTime: TimeInterval
    let recentErrorCount: Int
    let uptime: TimeInterval

    var isProductionReady: Bool {
        systemHealth != .critical && averageResponseTime < 0.5
    }
}
