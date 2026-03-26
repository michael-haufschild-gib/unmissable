// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Unmissable",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Unmissable",
            targets: ["Unmissable"]
        ),
    ],
    dependencies: [
        // OAuth 2.0 for Google Calendar
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "2.0.0"),
        // SQLite database
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        // Keychain access
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        // Global keyboard shortcuts
        .package(url: "https://github.com/Clipy/Magnet.git", from: "3.4.0"),
        // Snapshot testing
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.19.1"),
        // Auto-updates
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.0"),
        // Note: SwiftFormat and SwiftLint installed via Homebrew (brew install swiftformat swiftlint)
    ],
    targets: [
        .executableTarget(
            name: "Unmissable",
            dependencies: [
                .product(name: "AppAuth", package: "AppAuth-iOS"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "Magnet", package: "Magnet"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Unmissable",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TestSupport",
            dependencies: [
                "Unmissable",
            ],
            path: "Tests/TestSupport"
        ),
        .testTarget(
            name: "UnmissableTests",
            dependencies: [
                "Unmissable",
                "TestSupport",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/UnmissableTests",
            plugins: [
                .plugin(name: "LintGatePlugin"),
            ]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "Unmissable",
            ],
            path: "Tests/IntegrationTests",
            plugins: [
                .plugin(name: "LintGatePlugin"),
            ]
        ),
        .testTarget(
            name: "SnapshotTests",
            dependencies: [
                "Unmissable",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/SnapshotTests",
            exclude: [
                "__Snapshots__",
            ],
            plugins: [
                .plugin(name: "LintGatePlugin"),
            ]
        ),
        .testTarget(
            name: "E2ETests",
            dependencies: [
                "Unmissable",
                "TestSupport",
            ],
            path: "Tests/E2ETests",
            plugins: [
                .plugin(name: "LintGatePlugin"),
            ]
        ),
        .plugin(
            name: "LintGatePlugin",
            capability: .buildTool(),
            path: "Plugins/LintGatePlugin"
        ),
    ]
)
