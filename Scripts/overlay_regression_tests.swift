#!/usr/bin/env swift

import Foundation

struct XCTestCluster {
    let name: String
    let onlyTesting: [String]
}

private let scheme = "Unmissable"
private let destination = "platform=macOS"
private let executedPattern = #"Executed [1-9][0-9]* test"#

private func projectRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Scripts
        .deletingLastPathComponent() // project root
}

@discardableResult
private func runCluster(_ cluster: XCTestCluster, in projectURL: URL) -> Bool {
    print("🧪 \(cluster.name)")

    let process = Process()
    process.currentDirectoryURL = projectURL
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

    var args = ["-scheme", scheme, "-destination", destination, "test"]
    args.append(contentsOf: cluster.onlyTesting.flatMap { ["-only-testing:\($0)"] })
    process.arguments = args

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    do {
        try process.run()
    } catch {
        fputs("❌ Failed to start xcodebuild: \(error.localizedDescription)\n", stderr)
        return false
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let output = String(data: outputData, encoding: .utf8) ?? ""
    print(output)

    guard process.terminationStatus == 0 else {
        fputs("❌ \(cluster.name) failed with exit code \(process.terminationStatus)\n", stderr)
        return false
    }

    guard output.range(of: executedPattern, options: .regularExpression) != nil else {
        fputs("❌ \(cluster.name) executed zero tests (failing to avoid false confidence)\n", stderr)
        return false
    }

    print("✅ \(cluster.name) passed with executed XCTest coverage")
    return true
}

let clusters = [
    XCTestCluster(
        name: "Overlay interaction regression suite",
        onlyTesting: [
            "UnmissableTests/OverlayAccuracyAndInteractionTests",
            "UnmissableTests/OverlaySnoozeAndDismissTests",
        ]
    ),
    XCTestCluster(
        name: "Scheduling and integration regression suite",
        onlyTesting: [
            "UnmissableTests/EventSchedulerComprehensiveTests",
            "UnmissableTests/SystemIntegrationTests",
            "UnmissableTests/AppStateDisconnectCleanupTests",
        ]
    ),
]

let root = projectRoot()
var hasFailure = false
for cluster in clusters {
    if !runCluster(cluster, in: root) {
        hasFailure = true
    }
}

if hasFailure {
    fputs("❌ Overlay regression validation failed\n", stderr)
    exit(1)
}

print("🎯 Overlay regression validation complete")
