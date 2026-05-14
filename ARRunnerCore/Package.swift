// swift-tools-version: 6.0
import PackageDescription

// StrictConcurrency is enabled by default in Swift 6 language mode — D8 still in effect.
// Do NOT add .enableUpcomingFeature("StrictConcurrency"): it is a hard error under Swift 6.0
// (tolerated silently by newer toolchains like 6.3, which is why this slipped past local builds).
let strictConcurrencySettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
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
