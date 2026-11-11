// swift-tools-version: 5.9
import PackageDescription

// Pure-Swift domain logic for Anchor: no AppKit, SwiftUI or SwiftData.
// Builds and tests on macOS and Linux (`swift test`).
let package = Package(
    name: "AnchorCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnchorCore", targets: ["AnchorCore"]),
    ],
    targets: [
        .target(name: "AnchorCore"),
        .testTarget(name: "AnchorCoreTests", dependencies: ["AnchorCore"]),
    ]
)
