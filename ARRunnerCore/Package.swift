// swift-tools-version: 6.0
import PackageDescription

let strictConcurrencySettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("StrictConcurrency")
]

let package = Package(
    name: "ARRunnerCore",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11)
    ],
    products: [
        .library(
            name: "ARRunnerCore",
            targets: ["ARRunnerCore"]
        )
    ],
    targets: [
        .target(
            name: "ARRunnerCore",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "ARRunnerCoreTests",
            dependencies: ["ARRunnerCore"],
            swiftSettings: strictConcurrencySettings
        )
    ],
    swiftLanguageModes: [.v6]
)
