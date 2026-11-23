// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Stagehand",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CGVirtualDisplayPrivate", path: "Sources/CGVirtualDisplayPrivate"),
        .executableTarget(
            name: "Stagehand",
            dependencies: ["CGVirtualDisplayPrivate"],
            path: "Sources/Stagehand",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
