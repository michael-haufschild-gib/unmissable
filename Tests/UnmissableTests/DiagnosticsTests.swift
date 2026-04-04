import Foundation
@testable import Unmissable
import XCTest

final class DiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppDiagnostics.recorder.clear()
    }

    override func tearDown() {
        AppDiagnostics.recorder.clear()
        super.tearDown()
    }

    // MARK: - Gating

    func testIsEnabled_inDebugBuild_returnsTrue() {
        #if DEBUG
            XCTAssertTrue(AppDiagnostics.isEnabled)
        #endif
    }

    // MARK: - Recording

    func testRecord_whenEnabled_appendsWithCorrectFields() throws {
        AppDiagnostics.record(component: "Test", phase: "check", outcome: .info)

        let record = try XCTUnwrap(AppDiagnostics.recorder.snapshot().first)
        XCTAssertEqual(record.component, "Test")
        XCTAssertEqual(record.phase, "check")
        XCTAssertEqual(record.outcome, .info)
        XCTAssertEqual(record.sessionId, AppDiagnostics.sessionId)
    }

    func testRecord_metadataClosureIsEvaluated() throws {
        var closureCalled = false
        AppDiagnostics.record(component: "Test", phase: "meta") {
            closureCalled = true
            return ["key": "value"]
        }

        XCTAssertTrue(closureCalled)
        let record = try XCTUnwrap(AppDiagnostics.recorder.snapshot().first)
        XCTAssertEqual(record.metadata["key"], "value")
    }

    // MARK: - Session ID

    func testSessionId_isStableUUIDFormat() throws {
        let id1 = AppDiagnostics.sessionId
        let id2 = AppDiagnostics.sessionId
        XCTAssertEqual(id1, id2)
        // Verify it's a valid UUID by parsing
        let parsed = try XCTUnwrap(UUID(uuidString: id1), "Session ID should be valid UUID")
        XCTAssertEqual(parsed.uuidString.lowercased(), id1.lowercased())
    }

    // MARK: - Flow Tracking

    func testStartAndEndFlow_correlatesViaFlowId() throws {
        let flow = AppDiagnostics.startFlow("testOp", component: "TestComp")
        // Flow ID is a valid UUID
        let parsedFlowId = try XCTUnwrap(UUID(uuidString: flow.flowId), "Flow ID should be valid UUID")
        XCTAssertEqual(parsedFlowId.uuidString.lowercased(), flow.flowId.lowercased())

        AppDiagnostics.endFlow(flow, component: "TestComp", outcome: .success) {
            ["result": "ok"]
        }

        let records = AppDiagnostics.recorder.snapshot()
        let startRecord = try XCTUnwrap(records.first, "Should have start record")
        let endRecord = try XCTUnwrap(records.last, "Should have end record")

        // Both records share the same flowId
        XCTAssertEqual(startRecord.flowId, endRecord.flowId)
        XCTAssertEqual(startRecord.flowId, flow.flowId)

        // Start record
        XCTAssertEqual(startRecord.phase, "testOp.start")
        XCTAssertEqual(startRecord.outcome, .info)

        // End record
        XCTAssertEqual(endRecord.phase, "testOp.end")
        XCTAssertEqual(endRecord.outcome, .success)
        let durationMs = try XCTUnwrap(endRecord.durationMs, "End record should have duration")
        XCTAssertGreaterThanOrEqual(durationMs, 0, "Duration should be non-negative")
        XCTAssertEqual(endRecord.metadata["result"], "ok")
    }

    // MARK: - Ring Buffer Bounds

    func testFlightRecorder_respectsCapacity_dropsOldest() {
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
        XCTAssertEqual(snapshot[0].phase, "item2")
        XCTAssertEqual(snapshot[1].phase, "item3")
        XCTAssertEqual(snapshot[2].phase, "item4")
    }

    func testFlightRecorder_clear_removesAllRecords() {
        AppDiagnostics.record(component: "Test", phase: "one")
        AppDiagnostics.record(component: "Test", phase: "two")
        XCTAssertEqual(AppDiagnostics.recorder.snapshot().first?.phase, "one")

        AppDiagnostics.recorder.clear()
        // After clear, a new record should be the only one
        AppDiagnostics.record(component: "Test", phase: "after-clear")
        XCTAssertEqual(AppDiagnostics.recorder.snapshot().first?.phase, "after-clear")
        XCTAssertNil(
            AppDiagnostics.recorder.snapshot().dropFirst().first,
            "Should have exactly one record after clear + one append",
        )
    }

    func testFlightRecorder_tail_returnsCorrectLastN() {
        for i in 0 ..< 10 {
            AppDiagnostics.record(component: "Test", phase: "item\(i)")
        }

        let tail = AppDiagnostics.recorder.tail(3)
        XCTAssertEqual(tail[0].phase, "item7")
        XCTAssertEqual(tail[1].phase, "item8")
        XCTAssertEqual(tail[2].phase, "item9")
    }

    // MARK: - JSONL Export

    func testExportJSONL_producesDecodableRecords() throws {
        AppDiagnostics.record(component: "A", phase: "start", outcome: .info) {
            ["key": "val"]
        }
        AppDiagnostics.record(component: "B", phase: "end", outcome: .success)

        let data = AppDiagnostics.recorder.exportJSONL()
        let string = try XCTUnwrap(
            String(data: data, encoding: .utf8),
            "JSONL export should be valid UTF-8",
        )

        let lines = string.split(separator: "\n")
        let firstLineData = try Data(XCTUnwrap(lines.first).utf8)
        let firstDecoded = try JSONDecoder.diagnosticDecoder.decode(
            DiagnosticRecord.self,
            from: firstLineData,
        )
        XCTAssertEqual(firstDecoded.component, "A")
        XCTAssertEqual(firstDecoded.metadata["key"], "val")

        let secondLineData = try Data(XCTUnwrap(lines.dropFirst().first).utf8)
        let secondDecoded = try JSONDecoder.diagnosticDecoder.decode(
            DiagnosticRecord.self,
            from: secondLineData,
        )
        XCTAssertEqual(secondDecoded.component, "B")
        XCTAssertEqual(secondDecoded.sessionId, AppDiagnostics.sessionId)
    }

    // MARK: - DiagnosticRecord Summary

    func testRecordSummary_includesAllFields() {
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
        XCTAssertEqual(
            record.summary,
            "Sync.fetch=success 42ms flow=flow-123 count=5",
        )
    }

    // MARK: - Bug Book Export

    func testBugBookExport_containsSessionAndStateAndFailures() throws {
        AppDiagnostics.record(component: "Test", phase: "action", outcome: .failure) {
            ["detail": "something broke"]
        }

        let book = DiagnosticsBookExporter.export(
            stateSnapshot: ["alerts": "2", "overlay": "false"],
            testContext: ["testName": "myTest"],
        )

        let lines = book.components(separatedBy: "\n")

        // Verify header
        XCTAssertEqual(lines[0], "# Unmissable Diagnostic Report")

        // Verify the state snapshot section has the injected values
        let alertLine = try XCTUnwrap(
            lines.first { $0 == "- **alerts**: 2" },
            "Bug book should contain alerts state line",
        )
        XCTAssertEqual(alertLine, "- **alerts**: 2")

        // Verify test context
        let testNameLine = try XCTUnwrap(
            lines.first { $0 == "- **testName**: myTest" },
            "Bug book should contain test context",
        )
        XCTAssertEqual(testNameLine, "- **testName**: myTest")

        // Verify failures section exists with the failure record
        let failureHeader = try XCTUnwrap(
            lines.first { $0.hasPrefix("## Failures") },
            "Bug book should contain Failures section",
        )
        XCTAssertEqual(failureHeader, "## Failures (1)")
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
