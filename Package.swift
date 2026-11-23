// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Stagehand",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "CGVirtualDisplayPrivate", path: "Sources/CGVirtualDisplayPrivate"),
        .executableTarget(
            name: "Stagehand",
            dependencies: [
                "CGVirtualDisplayPrivate",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Stagehand",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                // Sparkle.framework is embedded in Contents/Frameworks by scripts/build.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
