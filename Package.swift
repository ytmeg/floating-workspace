// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatingWorkspace",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FloatingWorkspaceCore", targets: ["FloatingWorkspaceCore"]),
        .executable(name: "FloatingWorkspace", targets: ["FloatingWorkspace"])
    ],
    targets: [
        .target(name: "FloatingWorkspaceCore", path: "Sources/FloatingWorkspaceCore"),
        .executableTarget(
            name: "FloatingWorkspace",
            dependencies: ["FloatingWorkspaceCore"],
            path: "Sources/FloatingWorkspace"
        ),
        .testTarget(
            name: "FloatingWorkspaceCoreTests",
            dependencies: ["FloatingWorkspaceCore", "FloatingWorkspace"],
            path: "Tests/FloatingWorkspaceCoreTests"
        )
    ]
)
