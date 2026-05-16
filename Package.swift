// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentsBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AgentsBarCore",
            targets: ["AgentsBarCore"]
        ),
        .executable(
            name: "AgentsBar",
            targets: ["AgentsBar"]
        )
    ],
    targets: [
        .target(
            name: "AgentsBarCore"
        ),
        .executableTarget(
            name: "AgentsBar",
            dependencies: ["AgentsBarCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AgentsBarCoreTests",
            dependencies: ["AgentsBarCore"]
        )
    ]
)
