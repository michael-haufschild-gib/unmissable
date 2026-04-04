import Foundation
import OSLog

/// Central diagnostics facade. Routes structured events to both OSLog and the
/// in-memory `FlightRecorder` when deep diagnostics are enabled. When disabled,
/// `record()` is a no-op — no allocation, no OSLog write. Normal info/warning/error
/// logging continues via each manager's own `Logger(category:)` in all builds.
///
/// **Static/global by design** — AppDelegate and early bootstrap code need
/// tracing before the DI container exists. The recorder is cheap (ring buffer
/// protected by an unfair lock) and never touches disk unless explicitly exported.
///
/// ## Gating
/// - **DEBUG builds**: deep diagnostics enabled by default (both OSLog + FlightRecorder).
/// - **Release builds**: deep diagnostics disabled. Can be enabled via
///   `UserDefaults(key: "com.unmissable.diagnostics.enabled")` or the
///   `UNMISSABLE_DIAGNOSTICS` environment variable — intended for field debugging,
///   not end-user UI.
nonisolated enum AppDiagnostics {
    // MARK: - Session Identity

    /// Unique identifier for this app launch. Set once, never changes.
    static let sessionId: String = UUID().uuidString

    // MARK: - Infrastructure

    /// Shared flight recorder. Accumulates records across the entire session.
    static let recorder = FlightRecorder()

    private static let logger = Logger(category: "Diagnostics")

    // MARK: - Gating

    /// Whether deep (high-volume structured) diagnostics are enabled.
    /// Cheap to check — no allocation, no I/O.
    static var isEnabled: Bool {
        #if DEBUG
            return true
        #else
            return _releaseOverrideEnabled
        #endif
    }

    /// Cached release-mode override. Computed once on first access.
    /// Only `UNMISSABLE_DIAGNOSTICS=1` (or `true`/`yes`/`on`) enables;
    /// `=0`, `=false`, or empty string do not.
    private static let _releaseOverrideEnabled: Bool = {
        if let value = ProcessInfo.processInfo.environment["UNMISSABLE_DIAGNOSTICS"] {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "on"].contains(normalized) {
                return true
            }
        }
        return UserDefaults.standard.bool(forKey: "com.unmissable.diagnostics.enabled")
    }()

    // MARK: - Recording

    /// Records a structured diagnostic event.
    ///
    /// The `metadata` closure is only evaluated when diagnostics are enabled,
    /// so callers don't pay string-interpolation cost in production.
    ///
    /// - Parameters:
    ///   - component: Subsystem name (e.g., "SyncManager", "EventScheduler").
    ///   - phase: Step within the operation (e.g., "start", "fetch", "save").
    ///   - outcome: Result of this phase.
    ///   - flowId: Optional flow correlation ID from `startFlow()`.
    ///   - durationMs: Wall-clock duration in milliseconds (nil for instant events).
    ///   - metadata: Lazy key-value context. Evaluated only when enabled.
    static func record(
        component: String,
        phase: String,
        outcome: DiagnosticRecord.Outcome = .info,
        flowId: String? = nil,
        durationMs: Int? = nil,
        metadata: () -> [String: String] = { [:] },
    ) {
        guard isEnabled else { return }

        let record = DiagnosticRecord(
            timestamp: Date(),
            sessionId: sessionId,
            flowId: flowId,
            component: component,
            phase: phase,
            outcome: outcome,
            durationMs: durationMs,
            metadata: metadata(),
        )

        recorder.append(record)
        logger.debug("\(record.summary, privacy: .public)")
    }

    // MARK: - Flow Tracking

    /// Starts a named flow and returns a context for correlation.
    /// Pass the context to `endFlow()` when the operation completes.
    static func startFlow(_ name: String, component: String) -> FlowContext {
        let context = FlowContext(
            flowId: UUID().uuidString,
            name: name,
            startTime: Date(),
        )

        record(
            component: component,
            phase: "\(name).start",
            outcome: .info,
            flowId: context.flowId,
        )

        return context
    }

    /// Ends a previously started flow, recording duration and outcome.
    static func endFlow(
        _ context: FlowContext,
        component: String,
        outcome: DiagnosticRecord.Outcome = .success,
        metadata: () -> [String: String] = { [:] },
    ) {
        let durationMs = Int(Date().timeIntervalSince(context.startTime) * millisecondsPerSecond)

        record(
            component: component,
            phase: "\(context.name).end",
            outcome: outcome,
            flowId: context.flowId,
            durationMs: durationMs,
            metadata: metadata,
        )
    }

    /// Milliseconds per second for duration calculations.
    private static let millisecondsPerSecond: Double = 1000
}
