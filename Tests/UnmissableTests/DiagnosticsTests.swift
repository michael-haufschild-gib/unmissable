import Foundation
import Testing
@testable import Unmissable

/// Shared AppDiagnostics.recorder singleton requires serial execution to prevent cross-test interference.
@Suite(.serialized)
struct DiagnosticsTests {
    init() {
        AppDiagnostics.recorder.clear()
    }

    // MARK: - Gating

    @Test
    func isEnabled_inDebugBuild_returnsTrue() {
        #if DEBUG
            #expect(AppDiagnostics.isEnabled)
        #endif
    }

    // MARK: - Recording

    @Test
    func record_whenEnabled_appendsWithCorrectFields() throws {
        AppDiagnostics.record(component: "Test", phase: "check", outcome: .info)

        let record = try #require(AppDiagnostics.recorder.snapshot().first)
        #expect(record.component == "Test")
        #expect(record.phase == "check")
        #expect(record.outcome == .info)
        #expect(record.sessionId == AppDiagnostics.sessionId)
    }

    @Test
    func record_metadataClosureIsEvaluated() throws {
        var closureCalled = false
        AppDiagnostics.record(component: "Test", phase: "meta") {
            closureCalled = true
            return ["key": "value"]
        }

        #expect(closureCalled)
        let record = try #require(AppDiagnostics.recorder.snapshot().first)
        #expect(record.metadata["key"] == "value")
    }

    // MARK: - Session ID

    @Test
    func sessionId_isStableUUIDFormat() throws {
        let id1 = AppDiagnostics.sessionId
        let id2 = AppDiagnostics.sessionId
        #expect(id1 == id2)
        // Verify it's a valid UUID by parsing
        let parsed = try #require(UUID(uuidString: id1), "Session ID should be valid UUID")
        #expect(parsed.uuidString.lowercased() == id1.lowercased())
    }

    // MARK: - Flow Tracking

    @Test
    func startAndEndFlow_correlatesViaFlowId() throws {
        let flow = AppDiagnostics.startFlow("testOp", component: "TestComp")
        // Flow ID is a valid UUID
        let parsedFlowId = try #require(UUID(uuidString: flow.flowId), "Flow ID should be valid UUID")
        #expect(parsedFlowId.uuidString.lowercased() == flow.flowId.lowercased())

        AppDiagnostics.endFlow(flow, component: "TestComp", outcome: .success) {
            ["result": "ok"]
        }

        let records = AppDiagnostics.recorder.snapshot()
        let startRecord = try #require(records.first, "Should have start record")
        let endRecord = try #require(records.last, "Should have end record")

        // Both records share the same flowId
        #expect(startRecord.flowId == endRecord.flowId)
        #expect(startRecord.flowId == flow.flowId)

        // Start record
        #expect(startRecord.phase == "testOp.start")
        #expect(startRecord.outcome == .info)

        // End record
        #expect(endRecord.phase == "testOp.end")
        #expect(endRecord.outcome == .success)
        let durationMs = try #require(endRecord.durationMs, "End record should have duration")
        #expect(durationMs >= 0, "Duration should be non-negative")
        #expect(endRecord.metadata["result"] == "ok")
    }

    // MARK: - Ring Buffer Bounds

    @Test
    func flightRecorder_respectsCapacity_dropsOldest() {
        let smallRecorder = FlightRecorder(capacity: 3)

        for i in 0 ..< 5 {
            smallRecorder.append(DiagnosticRecord(
                timestamp: Date(),
                sessionId: "test",
                flowId: nil,
                component: "Test",
                phase: "item\(i)",
                outcome: .info,
                durationMs: nil,
                metadata: [:],
            ))
        }

        // Oldest records (0, 1) dropped; newest (2, 3, 4) remain
        let snapshot = smallRecorder.snapshot()
        #expect(snapshot[0].phase == "item2")
        #expect(snapshot[1].phase == "item3")
        #expect(snapshot[2].phase == "item4")
    }

    @Test
    func flightRecorder_clear_removesAllRecords() {
        AppDiagnostics.record(component: "Test", phase: "one")
        AppDiagnostics.record(component: "Test", phase: "two")
        #expect(AppDiagnostics.recorder.snapshot().first?.phase == "one")

        AppDiagnostics.recorder.clear()
        // After clear, a new record should be the only one
        AppDiagnostics.record(component: "Test", phase: "after-clear")
        #expect(AppDiagnostics.recorder.snapshot().first?.phase == "after-clear")
        #expect(
            AppDiagnostics.recorder.snapshot().dropFirst().first == nil,
            "Should have exactly one record after clear + one append",
        )
    }

    @Test
    func flightRecorder_tail_returnsCorrectLastN() {
        for i in 0 ..< 10 {
            AppDiagnostics.record(component: "Test", phase: "item\(i)")
        }

        let tail = AppDiagnostics.recorder.tail(3)
        #expect(tail[0].phase == "item7")
        #expect(tail[1].phase == "item8")
        #expect(tail[2].phase == "item9")
    }

    // MARK: - JSONL Export

    @Test
    func exportJSONL_producesDecodableRecords() throws {
        AppDiagnostics.record(component: "A", phase: "start", outcome: .info) {
            ["key": "val"]
        }
        AppDiagnostics.record(component: "B", phase: "end", outcome: .success)

        let data = AppDiagnostics.recorder.exportJSONL()
        let string = try #require(
            String(data: data, encoding: .utf8),
            "JSONL export should be valid UTF-8",
        )

        let lines = string.split(separator: "\n")
        let firstLine = try #require(lines.first)
        let firstLineData = Data(firstLine.utf8)
        let firstDecoded = try JSONDecoder.diagnosticDecoder.decode(
            DiagnosticRecord.self,
            from: firstLineData,
        )
        #expect(firstDecoded.component == "A")
        #expect(firstDecoded.metadata["key"] == "val")

        let secondLine = try #require(lines.dropFirst().first)
        let secondLineData = Data(secondLine.utf8)
        let secondDecoded = try JSONDecoder.diagnosticDecoder.decode(
            DiagnosticRecord.self,
            from: secondLineData,
        )
        #expect(secondDecoded.component == "B")
        #expect(secondDecoded.sessionId == AppDiagnostics.sessionId)
    }

    // MARK: - DiagnosticRecord Summary

    @Test
    func recordSummary_includesAllFields() {
        let record = DiagnosticRecord(
            timestamp: Date(),
            sessionId: "sess",
            flowId: "flow-12345678-abcd",
            component: "Sync",
            phase: "fetch",
            outcome: .success,
            durationMs: 42,
            metadata: ["count": "5"],
        )

        // Assert exact summary format
        #expect(
            record.summary == "Sync.fetch=success 42ms flow=flow-123 count=5",
        )
    }

    // MARK: - Bug Book Export

    @Test
    func bugBookExport_containsSessionAndStateAndFailures() throws {
        AppDiagnostics.record(component: "Test", phase: "action", outcome: .failure) {
            ["detail": "something broke"]
        }

        let book = DiagnosticsBookExporter.export(
            stateSnapshot: ["alerts": "2", "overlay": "false"],
            testContext: ["testName": "myTest"],
        )

        let lines = book.components(separatedBy: "\n")

        // Verify header
        #expect(lines[0] == "# Unmissable Diagnostic Report")

        // Verify the state snapshot section has the injected values
        let alertLine = try #require(
            lines.first { $0 == "- **alerts**: 2" },
            "Bug book should contain alerts state line",
        )
        #expect(alertLine == "- **alerts**: 2")

        // Verify test context
        let testNameLine = try #require(
            lines.first { $0 == "- **testName**: myTest" },
            "Bug book should contain test context",
        )
        #expect(testNameLine == "- **testName**: myTest")

        // Verify failures section exists with the failure record
        let failureHeader = try #require(
            lines.first { $0.hasPrefix("## Failures") },
            "Bug book should contain Failures section",
        )
        #expect(failureHeader == "## Failures (1)")
    }
}

// MARK: - Test Helpers

private extension JSONDecoder {
    static let diagnosticDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
