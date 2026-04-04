// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Unmissable",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Unmissable",
            targets: ["Unmissable"],
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
        // Deterministic clocks and concurrency testing utilities
        .package(url: "https://github.com/pointfreeco/swift-clocks.git", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras.git", from: "1.0.0"),
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
                .defaultIsolation(MainActor.self),
            ]
        ),
        .target(
            name: "TestSupport",
            dependencies: [
                "Unmissable",
                .product(name: "Clocks", package: "swift-clocks"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/TestSupport",
        ),
        .testTarget(
            name: "UnmissableTests",
            dependencies: [
                "Unmissable",
                "TestSupport",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/UnmissableTests",
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "Unmissable",
            ],
            path: "Tests/IntegrationTests",
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
        ),
        .testTarget(
            name: "E2ETests",
            dependencies: [
                "Unmissable",
                "TestSupport",
            ],
            path: "Tests/E2ETests",
        ),
    ],
)

// MARK: - ApproachableConcurrency feature flags (low-risk, Swift 6.3)

let approachableConcurrencyFlags: [SwiftSetting] = [
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    // GlobalActorIsolatedTypesUsability, InferSendableFromCaptures, and
    // DisableOutwardActorInference are already enabled by default in Swift 6.
]

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + approachableConcurrencyFlags
}
