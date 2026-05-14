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

XcodeGen reads `project.yml` and generates the workspace and project files needed for Apple development.
The generated workspace is `AR-Runner.xcworkspace`.

## Open the workspace

```bash
open AR-Runner.xcworkspace
```

## Shared package layout

`ARRunnerCore` is the shared local Swift Package Manager dependency used by the app and widget targets.
The package contains shared workout models, WatchConnectivity contracts, HUD layout presets, and side-store abstractions.

## Capabilities and signing

Some project operations only work on a Mac:

- code signing and provisioning
- enabling or adjusting capabilities in Signing & Capabilities
- simulator runs and on-device deployment
- verifying HealthKit, Bluetooth, WidgetKit, and WatchConnectivity behavior

## Decision references

Scaffolding follows the locked decisions in `.squad/decisions.md`:

- D1 — watch owns BLE directly
- D2 — watchOS 11 / iOS 18 minimums
- D3 — running-first UX with sport-agnostic core models
- D5 — watch-only workouts remain supported
- D6 — curated HUD presets ship at build time
- D7 — App Intents use foreground launch for workout takeover
- D8 — Swift 6 strict concurrency from day one
- D9 — HealthKit + lightweight AR metadata side-store
