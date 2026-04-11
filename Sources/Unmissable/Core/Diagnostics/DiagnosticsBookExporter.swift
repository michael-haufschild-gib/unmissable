import Foundation

/// Produces a human-readable "bug book" markdown document from the current
/// diagnostics state. Designed for AI agent consumption on test failure
/// or on-demand debug export from the running app.
enum DiagnosticsBookExporter {
    /// Maximum number of recent records included in the bug book.
    private static let tailRecordCount = 50

    /// Shared format style — reused across exports. `Date.ISO8601FormatStyle` is a
    /// `Sendable` value type, so it's safe to hold in a static let under Swift 6
    /// strict concurrency. Produces the same RFC 3339 / internet date-time format
    /// as `ISO8601DateFormatter()` with default options.
    private static let timestampFormatter = Date.ISO8601FormatStyle()

    /// Generates a markdown bug book.
    ///
    /// - Parameters:
    ///   - recorder: The flight recorder to snapshot.
    ///   - stateSnapshot: Key-value pairs describing current app state
    ///     (e.g., "scheduledAlerts" → "3", "overlayVisible" → "true").
    ///     Callers collect this from their local scope — the exporter
    ///     has no coupling to specific managers.
    ///   - testContext: Optional test-specific metadata (test name, clock time, etc.).
    /// - Returns: Markdown string.
    static func export(
        recorder: FlightRecorder = AppDiagnostics.recorder,
        stateSnapshot: [String: String] = [:],
        testContext: [String: String] = [:],
    ) -> String {
        var lines: [String] = []

        // Header
        lines.append("# Unmissable Diagnostic Report")
        lines.append("")
        lines.append("**Generated**: \(Self.timestampFormatter.format(Date()))")
        lines.append("**Session**: \(AppDiagnostics.sessionId)")
        lines.append("**Records in buffer**: \(recorder.count)")
        lines.append("")

        // Test context (if provided)
        if !testContext.isEmpty {
            let ctx = testContext
            lines.append("## Test Context")
            lines.append("")
            for (key, value) in ctx.sorted(by: { $0.key < $1.key }) {
                lines.append("- **\(key)**: \(value)")
            }
            lines.append("")
        }

        // State snapshot
        if !stateSnapshot.isEmpty {
            lines.append("## Current State")
            lines.append("")
            for (key, value) in stateSnapshot.sorted(by: { $0.key < $1.key }) {
                lines.append("- **\(key)**: \(value)")
            }
            lines.append("")
        }

        // Flow summary
        let records = recorder.snapshot()
        let flows = extractFlowSummaries(from: records)
        if !flows.isEmpty {
            lines.append("## Recent Flows")
            lines.append("")
            for flow in flows.suffix(flowSummaryLimit) {
                lines.append("- \(flow)")
            }
            lines.append("")
        }

        // Recent records (tail)
        let tail = recorder.tail(tailRecordCount)
        if !tail.isEmpty {
            lines.append("## Recent Records (\(tail.count) of \(recorder.count))")
            lines.append("")
            lines.append("```")
            for record in tail {
                let ts = Self.timestampFormatter.format(record.timestamp)
                lines.append("[\(ts)] \(record.summary)")
            }
            lines.append("```")
            lines.append("")
        }

        // Failure records
        let failures = records.filter { $0.outcome == .failure }
        if !failures.isEmpty {
            lines.append("## Failures (\(failures.count))")
            lines.append("")
            for failure in failures {
                let ts = Self.timestampFormatter.format(failure.timestamp)
                lines.append("- [\(ts)] \(failure.summary)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Writes the bug book to a file at the given URL.
    static func exportToFile(
        recorder: FlightRecorder = AppDiagnostics.recorder,
        stateSnapshot: [String: String] = [:],
        testContext: [String: String] = [:],
        url: URL,
    ) throws {
        let content = export(
            recorder: recorder,
            stateSnapshot: stateSnapshot,
            testContext: testContext,
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Maximum number of flow summaries shown.
    private static let flowSummaryLimit = 20

    /// Extracts one-line summaries from flow start/end pairs.
    private static func extractFlowSummaries(from records: [DiagnosticRecord]) -> [String] {
        // Group by flowId
        var flowStarts: [String: DiagnosticRecord] = [:]
        var flowEnds: [String: DiagnosticRecord] = [:]

        for record in records {
            guard let fid = record.flowId else { continue }
            if record.phase.hasSuffix(".start") {
                flowStarts[fid] = record
            } else if record.phase.hasSuffix(".end") {
                flowEnds[fid] = record
            }
        }

        var summaries: [String] = []
        for (fid, start) in flowStarts.sorted(by: { $0.value.timestamp < $1.value.timestamp }) {
            let fidShort = String(fid.prefix(DiagnosticConstants.flowIdDisplayLength))
            if let end = flowEnds[fid] {
                let dur = end.durationMs.map { "\($0)ms" } ?? "?"
                summaries.append(
                    "[\(fidShort)] \(start.component)/\(start.phase.replacingOccurrences(of: ".start", with: "")): \(end.outcome.rawValue) (\(dur))",
                )
            } else {
                summaries.append(
                    "[\(fidShort)] \(start.component)/\(start.phase.replacingOccurrences(of: ".start", with: "")): **in-progress**",
                )
            }
        }

        return summaries
    }
}
