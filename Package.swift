// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clipstack",
    platforms: [.macOS(.v12)],
    targets: [
        // Pure logic + system services. Kept separate from the executable so it
        // can be unit tested — test targets cannot depend on executable targets
        // reliably.
        .target(
            name: "ClipstackCore",
            path: "Sources/ClipstackCore",
            resources: [.process("Resources")]
        ),
        // Thin AppKit/SwiftUI shell.
        .executableTarget(
            name: "Clipstack",
            dependencies: ["ClipstackCore"],
            path: "Sources/Clipstack"
        ),
        .testTarget(
            name: "ClipstackCoreTests",
            dependencies: ["ClipstackCore"],
            path: "Tests/ClipstackCoreTests"
        ),
    ]
)
