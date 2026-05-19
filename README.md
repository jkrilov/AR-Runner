# AR-Runner

![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)
![Status](https://img.shields.io/badge/status-v0.4.0--rc1%20(TestFlight)-brightgreen.svg)

A native Apple Watch running app that drives a HUD on
[ActiveLook](https://www.activelook.net) AR glasses (Engo 2).
Watch is the primary device. Glasses give you the HUD.
**The phone is optional** — pair it if you want a live mirror and the glasses
battery readout, skip it otherwise.

Current build: `v0.4.0-rc1` (build 32). 186/186 tests green in `ARRunnerCore`.
Outside PRs are still paused — see [CONTRIBUTING.md](CONTRIBUTING.md).

## What works today

- **Live HUD on the glasses** — three-line, mixed-font layout:
  - Line 1: elapsed time + heart rate
  - Line 2: distance
  - Line 3: average pace
  - Four preloaded ALooK flash icons (clock, heart, ruler, stopwatch) draw
    alongside the values.
- **Persistent finish screen** — when the user taps Finish, the glasses render
  a Time + Distance summary that stays up until the next workout or a manual
  disconnect. The BLE link is not torn down by workout-stop.
- **User-managed BLE link** — pair the glasses once; the link persists across
  workouts and across app launches. See ADR-1 (`.squad/decisions.md`) for why
  the link is no longer workout-scoped.
- **HealthKit workout** — runs are recorded as `HKWorkout` via
  `HKWorkoutSession` + `HKLiveWorkoutBuilder`; the watch is the canonical
  HealthKit owner.
- **Live mirror on iPhone (optional)** — if a phone is paired, a tab shows
  live tick data plus the glasses battery percentage relayed from the watch
  over `WatchConnectivity`. No phone = no degradation on watch or glasses.
- **Smart Stack / Action Button launch** — tapping the workout entry from the
  Smart Stack hands off to the watch app which auto-starts the run.

## Repository layout

- `ARRunnerCore/` — Swift package. Platform-neutral models, BLE frame
  encoders, workout state machine, WC message schema, formatters. 186 tests,
  runs on Linux + macOS so SPM stays buildable in CI without Apple SDKs.
- `ARRunnerWatch/` — watchOS 11 app. Owns `HKWorkoutSession`, the
  ActiveLook `CBCentralManager`, and the workout view-model.
- `ARRunnerPhone/` — iOS 18 companion. Live mirror + future settings.
  Optional.
- `WidgetsPhone/`, `WidgetsWatch/` — WidgetKit extensions for Smart Stack
  and Action Button launch surfaces.

## Stack

- Swift 6 (strict concurrency), SwiftUI, watchOS 11 / iOS 18
- HealthKit on the watch
- ActiveLook SDK over CoreBluetooth (vendored under
  `ActiveLook*` paths — do not edit)
- XcodeGen-driven project (`AR-Runner.xcworkspace` is generated)

## Architecture notes worth knowing

- **Phone is never a requirement.** The contract: watch + glasses ship a
  complete experience. Anything that needs the phone (live mirror, battery
  readout, future settings) is additive.
- **Lens-flip framebuffer.** Engo 2 ships its display rotated relative to the
  wearer's frame of reference. All HUD Y coordinates are baked through
  `y_fb = 255 − wearer_top`, with rotation kept at 4 (topLR). See
  `RunningHUDFrame` for the conversion and
  `.squad/skills/activelook-hud-rendering` for the long version.
- **BLE write serialization + flow control.** Writes go through a serialized
  queue with a flow-control gate to keep `HKLiveWorkoutBuilder` ticks from
  flooding the link. Throttle is per-field, last-write-wins at ~1 Hz.
- **Curated layouts, no runtime upload.** Icons live as preloaded ALooK flash
  IDs baked onto the glasses (config name `ALooK`). The earlier approach
  of uploading custom icons via `cfgWrite` / `imgSave` is discarded.

## Bench testing

Per-RC bench scenarios live in `.squad/decisions.md` under the
**"Amber rc17 QA scenarios"** heading (2026-05-19). Five scopes:

- A — BLE link lifecycle past workout-stop
- B — Finish screen renders + persists
- C — Battery characteristic (0x180F / 2A19)
- D — Phone-optional contract
- E — Regression guards

The recommended bench order plus unit-test recommendations are in the same
section.

## Release pattern

- **Bundled-bump PRs.** Version bump and xcodegen project regeneration live
  in the same commit as the feature work — never split. CI rebuilds from
  the regenerated project.
- **Auto-release to TestFlight on green CI** for tagged `v*.*.*-rc*` builds.
  No manual step.
- **Tags are immutable.** A regression gets a new rc, never a rewritten one.

## Build

Generate the Xcode project on macOS, then build/run from Xcode:

```sh
brew install xcodegen
xcodegen generate
open AR-Runner.xcworkspace
```

Run the Core test suite without Xcode:

```sh
swift test --package-path ARRunnerCore
```

## Read next

- Product brief: `docs/planning/product-brief.md`
- Architecture: `docs/planning/architecture.md`
- watchOS plan: `docs/planning/watchos-architecture.md`
- Mac setup: `docs/dev/setup.md`
- CI workflows: `docs/dev/ci-workflows.md`
- TestFlight setup: `docs/dev/testflight-setup.md`
- Locked decisions + ADRs: `.squad/decisions.md`

## Team

- Joe — product direction
- Richards — Lead / architecture
- Killian — product strategy
- Laughlin — watchOS, HealthKit
- Weiss — ActiveLook BLE
- Amber — workout metrics + QA

## License

Apache 2.0 — see [LICENSE](LICENSE).

---

> **About `.squad/`** — AR-Runner is built using
> [Squad](https://github.com/bradygaster/squad) for AI agent orchestration.
> The `.squad/` directory holds the team's working memory (per-agent
> histories, decisions ledger). Browse if you're curious how the project
> came together.
