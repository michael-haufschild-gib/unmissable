import Foundation

/// A single structured diagnostic event captured by the diagnostics system.
/// Records are lightweight value types designed for ring-buffer storage and JSONL export.
/// Explicitly `nonisolated` so the `nonisolated` FlightRecorder can store and encode them.
nonisolated struct DiagnosticRecord: Codable {
    /// When this record was created.
    let timestamp: Date
    /// App launch session identifier — groups all records from one run.
    let sessionId: String
    /// Optional flow identifier — correlates records within a single operation
    /// (e.g., one sync cycle's fetch → save → notify chain).
    let flowId: String?
    /// Which subsystem produced this record.
    let component: String
    /// What step within the operation (e.g., "start", "fetch", "save", "end").
    let phase: String
    /// Result of the phase: success, failure, skipped, etc.
    let outcome: Outcome
    /// Wall-clock duration in milliseconds (nil for point-in-time events).
    let durationMs: Int?
    /// Redacted key-value context. All values must be pre-redacted by the caller.
    let metadata: [String: String]

    nonisolated enum Outcome: String, Codable {
        case success
        case failure
        case skipped
        case info
    }

    /// Compact single-line summary for Console.app / OSLog output.
    var summary: String {
        var parts = ["\(component).\(phase)=\(outcome.rawValue)"]
        if let ms = durationMs {
            parts.append("\(ms)ms")
        }
        if let fid = flowId {
            parts.append("flow=\(fid.prefix(DiagnosticConstants.flowIdDisplayLength))")
        }
        if !metadata.isEmpty {
            let kvs = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            parts.append(kvs)
        }
        return parts.joined(separator: " ")
    }
}

/// Tracks the lifecycle of a multi-step operation (e.g., a sync cycle).
/// Created by `AppDiagnostics.startFlow`, closed by `AppDiagnostics.endFlow`.
nonisolated struct FlowContext {
    let flowId: String
    let name: String
    let startTime: Date
}

/// Shared constants for the diagnostics subsystem.
nonisolated enum DiagnosticConstants {
    /// Number of characters shown from a flow ID in log summaries.
    static let flowIdDisplayLength = 8
}
