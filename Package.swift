// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatingWorkspace",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FloatingWorkspaceCore", targets: ["FloatingWorkspaceCore"])
    ],
    targets: [
        .target(name: "FloatingWorkspaceCore", path: "Sources/FloatingWorkspaceCore"),
        .testTarget(
            name: "FloatingWorkspaceCoreTests",
            dependencies: ["FloatingWorkspaceCore"],
            path: "Tests/FloatingWorkspaceCoreTests"
        )
    ]
)
