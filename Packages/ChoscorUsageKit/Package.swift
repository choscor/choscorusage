// swift-tools-version: 6.2
// Layered package: Core ← Providers ← Kit. The app imports only ChoscorUsageKit.
import PackageDescription

// Local package, so unsafe flags are permitted; they turn every warning into an error.
let strictSettings: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"])
]

let package = Package(
    name: "ChoscorUsageKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ChoscorUsageKit", targets: ["ChoscorUsageKit"])
    ],
    targets: [
        .target(name: "ChoscorUsageCore", swiftSettings: strictSettings),
        .target(
            name: "ChoscorUsageProviders",
            dependencies: ["ChoscorUsageCore"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "ChoscorUsageKit",
            dependencies: ["ChoscorUsageCore", "ChoscorUsageProviders"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "ChoscorUsageTestSupport",
            dependencies: ["ChoscorUsageCore"],
            path: "Tests/ChoscorUsageTestSupport",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "ChoscorUsageCoreTests",
            dependencies: ["ChoscorUsageCore"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "ChoscorUsageProvidersTests",
            dependencies: ["ChoscorUsageCore", "ChoscorUsageProviders", "ChoscorUsageTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "ChoscorUsageKitTests",
            dependencies: [
                "ChoscorUsageCore", "ChoscorUsageProviders", "ChoscorUsageKit", "ChoscorUsageTestSupport",
            ],
            swiftSettings: strictSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
