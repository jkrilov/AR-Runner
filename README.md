# AR-Runner

![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)
![Status](https://img.shields.io/badge/status-pre--v0.1%20scaffolding-yellow.svg)

> ⚠️ **Project Status: Pre-v0.1, scaffolding only.** This repository is the
> architectural scaffold for AR-Runner. There is no installable build yet —
> the watch, phone, and widget targets are stubs, and the BLE wrapper plus
> HealthKit integration are still ahead. Issues for discussion are welcome;
> outside PRs are paused until v0.1 lands (see [CONTRIBUTING.md](CONTRIBUTING.md)).

AR-Runner is a native Apple Watch and iPhone running companion for [ActiveLook](https://www.activelook.net) AR glasses.
The v0.1 foundation centers the workout on the watch, mirrors live state to the phone, and pushes HUD-friendly metrics to the glasses over BLE.

## What is in this repo

- `ARRunnerWatch` — watchOS 11 app shell for workout control, HealthKit sessions, and direct glasses connectivity
- `ARRunnerPhone` — iOS 18 companion app shell for live mirroring, settings, and post-run review
- `ARRunnerWidgets` — WidgetKit extension for Smart Stack and companion launch surfaces
- `ARRunnerCore` — shared Swift package for sport-agnostic models, messaging, and storage protocols

## Product shape

- Apple Watch is the workout authority and BLE owner for v0.1
- iPhone is the configuration cockpit and secondary live display
- ActiveLook glasses render curated HUD presets built from shared metric models
- HealthKit is the source of truth for workouts; AR-specific metadata stays in a small side-store

## Team

- Joe — product direction
- Laughlin — watchOS, HealthKit, Swift scaffolding
- Weiss — ActiveLook BLE and wrapper strategy
- Amber — workout metrics domain
- Richards — architecture and integration planning
- Killian — product brief and MVP scope

## Read next

- Product brief: `docs/planning/product-brief.md`
- Architecture: `docs/planning/architecture.md`
- watchOS plan: `docs/planning/watchos-architecture.md`
- Mac setup: `docs/dev/setup.md`
- Locked decisions: `.squad/decisions.md`

## Workflow notes

This repository is scaffolded with XcodeGen.
Generate the Apple project files on a Mac, not in this Windows workspace.
The generated workspace is `AR-Runner.xcworkspace`.

## License

Apache 2.0 — see [LICENSE](LICENSE).

---

> **About `.squad/`** — AR-Runner is built using [Squad](https://github.com/bradygaster/squad)
> for AI agent orchestration. The `.squad/` directory contains the team's working memory
> (per-agent histories, decisions ledger, orchestration logs). Browse if curious about how
> this project came together.
