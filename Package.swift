// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PastePlus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PastePlus", path: "Sources/PastePlus"),
        .testTarget(name: "PastePlusTests", dependencies: ["PastePlus"], path: "Tests/PastePlusTests"),
    ]
)
