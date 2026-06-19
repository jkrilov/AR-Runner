# AR-Runner — Copilot Instructions

## What this project is

AR-Runner is a **running app for Apple Watch** that drives a heads-up display
on **ActiveLook AR glasses** (Engo 2). Currently shipping on TestFlight at
**v0.6.3**. See `README.md` for the user-facing feature list.

## Repository layout

```
ARRunnerCore/           Shared Swift package — pure Swift, no Apple frameworks
  Sources/ARRunnerCore/
    Glasses/            HUD layout presets, frame builders, transport protocol
    Messaging/          WCSession message contracts (versioned, Codable)
    Models/             Workout metrics, sport types, units
    Protocols/          Cross-module protocol boundaries (testable)
    Storage/            AR-metadata side-store keyed by HKWorkout UUID
    Strava/             OAuth + upload types (no networking — see phone target)
    Workout/            WorkoutController actor, state machine
  Tests/                XCTest, runs on Linux Swift 6 CI

ARRunnerWatch/          watchOS app — HealthKit + BLE owner
  ActionButton/         App Intents wired to Action Button + Smart Stack
  Glasses/              CoreBluetooth ActiveLook driver, HUD rendering
  Settings/             Watch-side settings UI
  Sync/                 WCSession sender/receiver
  Views/                SwiftUI workout, finish, pause overlay views
  Workout/              HKWorkoutSession substrate, route/location wiring

ARRunnerPhone/          iOS companion app — optional
  Strava/               ASWebAuthenticationSession + token storage
  Sync/                 WCSession sender/receiver (mirror)
  Views/                Live mirror, map, settings

ARRunnerWidgets/        Smart Stack widget (shared by watch + phone targets)
Shared/                 Cross-target types (settings, small views)

Config/                 Generated entitlements + Info.plist (gitignored)
project.yml             XcodeGen source of truth — DO NOT commit .xcodeproj
VERSION                 Marketing version string (sourced by release tooling)
docs/                   Architecture + dev/ops documentation
.squad/                 AI team orchestration state — see "Squad" below
```

## Build & test

```bash
brew install xcodegen
xcodegen generate                       # regenerates AR-Runner.xcodeproj

# Core unit tests (Linux-compatible, fast)
cd ARRunnerCore && swift test

# App builds (mirrors ci-build.yml)
xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerWatch \
  -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
# Repeat for: ARRunnerPhone, ARRunnerWidgetsPhone, ARRunnerWidgetsWatch
```

CI runs three workflows (`ci-core-tests`, `ci-build`, `codeql`). All three
are required to merge. TestFlight releases auto-trigger from pre-release
tags `v*.*.*-*` via `release-testflight.yml`. See
`docs/dev/ci-workflows.md` and `docs/dev/testflight-setup.md`.

## Core conventions (binding)

1. **No Apple-framework imports in `ARRunnerCore`** — enforced by the Linux
   CI job. Use protocol boundaries; put HealthKit/CoreBluetooth/WatchKit
   code in the app shells.
2. **SPDX headers on every `.swift` file:**
   ```swift
   // SPDX-FileCopyrightText: 2026 Joe Krilov
   // SPDX-License-Identifier: Apache-2.0
   ```
3. **Swift 6 strict concurrency** is mandatory. `@preconcurrency import`
   only at vendor SDK boundaries (ActiveLook). Never add
   `.enableUpcomingFeature("StrictConcurrency")` flags.
4. **AsyncStream over Combine** for cross-module observation — compiles on
   Linux, Swift 6 first-class.
5. **Watch is BLE owner.** The watch talks directly to the glasses over
   BLE. The phone is never a workout-time dependency.
6. **Workout state and BLE link state are independent.** Stopping a workout
   does NOT disconnect glasses; only explicit user action disconnects.
7. **HealthKit is the source of truth** for run data. AR-specific metadata
   lives in a small side-store keyed by `HKWorkout.UUID`.
8. **No `.xcodeproj` committed** — `project.yml` (XcodeGen) is the source
   of truth. The bundle and `Config/` outputs are gitignored.
9. **Version bumps ship with the work.** `CURRENT_PROJECT_VERSION` in
   `project.yml` is bumped in the same PR as the feature/fix, not as a
   separate PR.
10. **No work on `main`.** All changes via `feat/`, `fix/`, `chore/`, or
    `spike/` branches → PR → review → merge. Doc-only changes are the
    one exception.

## Key API contracts

- **`GlassesFrameTransport`** (`ARRunnerCore/Glasses/`) — protocol that
  abstracts the BLE link. Watch implements; tests use a mock.
- **`WorkoutController`** actor (`ARRunnerCore/Workout/`) — owns workout
  lifecycle. `reportGlassesSignal(.disconnected)` never pauses the workout.
- **`WCMessage`** envelope (`ARRunnerCore/Messaging/`) — every WCSession
  payload is a versioned Codable struct with a `schemaVersion: Int`.

See `docs/architecture.md` for the full picture.

## Squad orchestration

This repo uses [Squad](https://github.com/bradygaster/squad) for AI team
coordination. Files under `.squad/` are governed by
`.github/agents/squad.agent.md`.

- **`.squad/team.md`** — roster (the `## Members` header is parsed by
  `sync-squad-labels.yml` — keep it verbatim).
- **`.squad/routing.md`** — who handles what.
- **`.squad/decisions.md`** — append-only ledger. Never edit directly:
  drop a file in `.squad/decisions/inbox/{agent}-{slug}.md`; Scribe merges.
- **`.squad/agents/{name}/charter.md`** — per-agent identity.
- **`.squad/agents/{name}/history.md`** — per-agent learnings, append-only.
  Each agent edits only its own history file.

Runtime state (gitignored): `.squad/orchestration-log/`, `.squad/log/`,
`.squad/decisions/inbox/`, `.squad/sessions/`, `.squad/.scratch/`,
`.squad-workstream`.

Append-only files use `merge=union` in `.gitattributes` so branch merges
combine entries automatically.

### Issue routing workflows

- `sync-squad-labels.yml` — generates `squad:{member}` labels from
  `team.md`.
- `squad-triage.yml` — when an issue gets the bare `squad` label, the Lead
  triages and adds a `squad:{member}` sub-label.
- `squad-issue-assign.yml` — routes labeled issues to the named member.
- `squad-heartbeat.yml` — event-based keep-alive.

### Conventions for agents

- The **coordinator dispatches, never implements.** Spawn the relevant
  domain agent instead of writing code inline.
- **Reviewer rejections lock out the original author** — a different agent
  must do the revision (see `squad.agent.md` → Reviewer Rejection Protocol).
- Parallel agents use git worktrees:
  `git worktree add ../AR-Runner-{agent}-{task}`.
