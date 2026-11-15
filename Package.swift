// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrowsNest",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CrowsNestCore"),
        .executableTarget(name: "crowsnest-bridge", dependencies: ["CrowsNestCore"]),
        .executableTarget(name: "CrowsNestApp", dependencies: ["CrowsNestCore"]),
        .testTarget(name: "CrowsNestCoreTests", dependencies: ["CrowsNestCore"]),
    ],
    swiftLanguageModes: [.v5]
)
