# Development Setup

AR-Runner's Apple targets are scaffolded with XcodeGen and a local Swift package.
Use a Mac for project generation, signing, simulator runs, and device testing.

## Required tools

- Xcode 16 or newer
- XcodeGen (`brew install xcodegen`)
- A watchOS 11 / iOS 18 toolchain

## Generate the project

From the repository root on macOS:

```bash
xcodegen generate
```

XcodeGen reads `project.yml` and generates the Xcode project file (`AR-Runner.xcodeproj`) needed for Apple development. Both the project bundle and the per-target `Config/` plists and entitlements are derived from `project.yml` and are gitignored — regenerate them with `xcodegen generate` after pulling.

## Open the project

```bash
open AR-Runner.xcodeproj
```

## Troubleshooting

### `Cannot find 'TypeName' in scope` for a file that exists on disk

You're looking at a stale generated `AR-Runner.xcodeproj`. The project bundle is gitignored and XcodeGen rebuilds it from `project.yml`, recursively including everything under each target's `sources` path. When a teammate adds a new `.swift` file in a feature branch, your local pbxproj doesn't know about it until you regenerate.

```bash
xcodegen generate
```

Re-run any time after pulling, switching branches, or noticing an unexpected "missing symbol" error for a file that clearly exists.

## Shared package layout

`ARRunnerCore` is the shared local Swift Package Manager dependency used
by the watch app, phone app, and widget targets. It contains workout
models, the `WorkoutController` actor, the `GlassesFrameTransport`
protocol, HUD layout presets, WatchConnectivity message contracts, the
AR-metadata side-store, and the Strava types. It imports only `Foundation`
so it builds and tests on Linux CI (no HealthKit, CoreBluetooth, WatchKit,
or UIKit imports — those live in the app shells).

## Capabilities and signing

Some project operations only work on a Mac:

- code signing and provisioning
- enabling or adjusting capabilities in Signing & Capabilities
- simulator runs and on-device deployment
- verifying HealthKit, Bluetooth, WidgetKit, and WatchConnectivity behavior

## Decision references

The locked architectural decisions live in `.squad/decisions.md`. See
also [`docs/architecture.md`](../architecture.md) for the current system
overview.
