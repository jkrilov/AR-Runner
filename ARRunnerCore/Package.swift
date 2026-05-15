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
        .watchOS(.v11),
        // Declared so `swift test` on a developer Mac picks a deployment
        // target where `AsyncStream` / `Task` are available. Linux CI ignores
        // this list; the app-shell xcodebuild matrix uses the per-target
        // iOS/watchOS deployment targets in `project.yml`.
        .macOS(.v14)
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
