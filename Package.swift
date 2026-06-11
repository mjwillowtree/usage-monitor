// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UsageMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "UsageMonitor",
            path: "Sources/UsageMonitor"
        )
    ]
)
