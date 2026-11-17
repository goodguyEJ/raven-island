// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RavenIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RavenIslandCore"),
        .executableTarget(name: "ravenisland-bridge", dependencies: ["RavenIslandCore"]),
        .systemLibrary(name: "IOHIDPrivate"),
        .executableTarget(name: "RavenIslandApp", dependencies: ["RavenIslandCore", "IOHIDPrivate"]),
        .testTarget(name: "RavenIslandCoreTests", dependencies: ["RavenIslandCore"]),
    ],
    swiftLanguageModes: [.v5]
)
