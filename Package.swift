// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgentSessions",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "AgentSessionsCore",
            targets: ["AgentSessionsCore"]
        ),
        .executable(
            name: "AgentSessions",
            targets: ["AgentSessions"]
        )
    ],
    targets: [
        .target(
            name: "AgentSessionsCore"
        ),
        .executableTarget(
            name: "AgentSessions",
            dependencies: ["AgentSessionsCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AgentSessionsCoreTests",
            dependencies: ["AgentSessionsCore"]
        )
    ]
)
