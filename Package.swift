// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpacedOut",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SpacedOutCore",
            targets: ["SpacedOutCore"]
        ),
        .executable(
            name: "SpacedOut",
            targets: ["SpacedOutApp"]
        )
    ],
    targets: [
        .target(
            name: "SpacedOutCore",
            path: "Sources/SpacedOutCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "SpacedOutApp",
            dependencies: ["SpacedOutCore"],
            path: "Sources/SpacedOutApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SpacedOutCoreTests",
            dependencies: ["SpacedOutCore"],
            path: "Tests/SpacedOutCoreTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
