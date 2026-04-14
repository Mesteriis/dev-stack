// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevStackMenu",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "DevStackCore",
            targets: ["DevStackCore"]
        ),
        .executable(
            name: "dx",
            targets: ["dx"]
        ),
        .executable(
            name: "DevStackMenu",
            targets: ["DevStackMenu"]
        ),
        .executable(
            name: "DevStackSmokeTests",
            targets: ["DevStackSmokeTests"]
        ),
    ],
    targets: [
        .target(
            name: "DevStackCore"
        ),
        .executableTarget(
            name: "dx",
            dependencies: ["DevStackCore"]
        ),
        .executableTarget(
            name: "DevStackMenu",
            dependencies: ["DevStackCore"]
        ),
        .executableTarget(
            name: "DevStackSmokeTests",
            dependencies: ["DevStackCore"]
        ),
    ]
)
