// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GPUStatCard",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "GPUStatCardCore",
            path: "Sources/GPUStatCardCore"
        ),
        .executableTarget(
            name: "GPUStatCard",
            dependencies: ["GPUStatCardCore"],
            path: "Sources/GPUStatCard"
        ),
    ]
)
