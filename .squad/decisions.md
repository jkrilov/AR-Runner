# Squad Decisions

> **Archive:** Full historical log (284KB) in `decisions-archive-2026-05-20.md`.

---

## Core Architecture (D1–D9, locked 2026-05-14)

### D1 — BLE ownership
Watch owns the BLE connection to ActiveLook glasses directly. Phone not required during workouts.

### D2 — OS targets
Minimum watchOS 11, iOS 18. Swift 6 strict concurrency.

### D3 — Multi-sport scope
Running-only in v0.1; core data models are sport-agnostic from day one.

### D4 — Glasses disconnect mid-run
Workout continues uninterrupted. Haptic alert, "HUD offline" indicator, auto-reconnect in background, gap logged in metadata.

### D5 — Watch-only mode
Watch + glasses can run full workout without phone. Phone is config cockpit + post-run review.

### D6 — HUD layout model
2–3 curated layout presets baked at build time. Phone picks between presets. Layout editor deferred to v1.

### D7 — Action Button / shortcut launch
Foreground launch to running workout view (matching native Apple Workout UX).

### D8 — Swift 6 strict concurrency
Mandatory from day one. Use `@preconcurrency import` at ActiveLook SDK boundary only. Do NOT add `.enableUpcomingFeature("StrictConcurrency")` flags — CI will reject them.

### D9 — Run history storage
1. **HealthKit** — primary run data (v0.1)
2. **Side store** — AR-specific metadata keyed by HKWorkout UUID (v0.1)
3. **CloudKit** — user config (v1)

---

## User Directives (binding)

| Date | Directive |
|------|-----------|
| 2026-05-14 | **No Direct Main** — all changes via feature branches + PRs. Naming: `feat/`, `spike/`, `fix/`, `chore/`. |
| 2026-05-14 | **Track Squad Logs** — `.squad/log/` and `.squad/orchestration-log/` tracked in git. |
| 2026-05-14 | **XcodeGen** — `project.yml` is source of truth. No `.xcodeproj` committed. |
| 2026-05-14 | **Claude Opus 4.7** — code-writing agents use `claude-opus-4.7-1m-internal`. Scribe/Killian stay on haiku. |
| 2026-05-17 | **Opus 4.7 (reaffirmed)** — any agent touching code must use Opus 4.7 1M context. Fallback: opus-4.6-1m → opus-4.6 → opus-4.5. Never Sonnet/Haiku for code. |
| 2026-05-18 | **Post-release stale-task sweep** — after shipping a pre-release, coordinator sweeps background tasks. |
| 2026-05-19 | **Bundle version bump in work PR** — `CURRENT_PROJECT_VERSION` bump goes in the same PR as the feature/fix. No separate bump PRs. |
| 2026-05-19 | **Phone is NEVER a requirement** — Watch + glasses must function fully without phone. Phone features degrade gracefully when offline. |
| 2026-05-19 | **Auto-release to TestFlight** — after CI green, tag and upload without waiting for explicit approval. Joe validates on TestFlight. |
| 2026-05-19 | **Engo 2 display: 15-level grayscale** — no colors. All HUD design uses intensity levels 0-15 (amber-on-black). |

---

## Standing Rules

1. **No Apple-framework imports in ARRunnerCore** — enforced by Linux CI. Use protocol boundaries.
2. **ActiveLook Visual Assets hard rule** — never commit assets/fonts/configs from `ActiveLook/Activelook-Visual-Assets` or `Config-Generator` (CC BY-NC-ND 4.0). Original art only.
3. **SPDX headers** on all `.swift` files: `// SPDX-FileCopyrightText: 2026 Joe Krilov` / `// SPDX-License-Identifier: Apache-2.0`
4. **AsyncStream over Combine** for cross-module observation. Compiles on Linux, Swift 6 first-class.
5. **Parallel agents use git worktrees** — `git worktree add ../AR-Runner-{agent}-{task}` for isolation.
6. **CI required checks**: `ci-core-tests` (Linux), `ci-build` (4-scheme macOS matrix), `codeql` (security-extended).

---

## Key ADRs

### BLE link lifecycle (locked v0.4+)
The BLE link to ActiveLook glasses is **user-managed, not workout-scoped**. Workout state and link state are independent state machines. Workout-stop does NOT disconnect. Only explicit user action disconnects.

### BLE write serialization (PR #55)
Writes serialize via `didWriteValueFor` callback (CheckedContinuation). Flow-control gate: wait for `isNotifying == true` on flow-control characteristic before sending commands. 2s safety timeout.

### Engo 2 lens-flip formula
`x_wearer = 303 − x_fb`, `y_wearer = 255 − y_fb`. Rotation=4 (topLR) + adjusted coordinates = right-side-up text. All coords must stay in `0..303 × 0..255` framebuffer space (off-screen = silently clipped, no error).

### Font heights (from ActiveLook Visual-Assets README)
F1=24px, F2=38px, F3=64px, F4=75px, F5=82px. Formula: `y_fb = 255 − wearer_top` (topLR anchors at top-right).

### TestFlight CI (release-testflight.yml)
- Tag `v*.*.*-*` auto-triggers; pure `v*.*.*` reserved for App Store (future).
- Also supports `workflow_dispatch` with `version` input.
- Version from tag, build number from `$GITHUB_RUN_NUMBER`.
- Signing: `Config/Signing.xcconfig` is single source of truth. Never pass `CODE_SIGN_STYLE`/`CODE_SIGN_IDENTITY` on CLI.
- Secrets: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_KEY_*` (×3), `BUILD_CERTIFICATE_P12_*` (×2), `KEYCHAIN_PASSWORD`.
- Xcode 16.4 pinned via `maxim-lobanov/setup-xcode@v1`.

### Strava OAuth (v0.5, PR #84)
- Endpoint: `https://www.strava.com/oauth/mobile/authorize`
- redirect_uri: `arrunner://ar-runner.app/callback`
- Authorization Callback Domain (Strava settings): `ar-runner.app`
- Dual-path: try `strava://` deep link first (canOpenURL), fall back to ASWebAuthenticationSession.
- `LSApplicationQueriesSchemes: [strava]` in project.yml.

---

## API Contracts (stable on main)

### GlassesFrameTransport protocol

```swift
public protocol GlassesFrameTransport: Sendable {
    var connectionState: GlassesConnectionState { get async }
    func connectionStates() async -> AsyncStream<GlassesConnectionState>
    func statusEvents() async -> AsyncStream<GlassesStatusEvent>
    func connect() async throws
    func disconnect() async throws
    func selectLayout(id: String) async throws
    func updateField(_ update: HUDFieldUpdate) async throws
    func updateFields(_ updates: [HUDFieldUpdate]) async throws
}
```

States: `disconnected | scanning | connecting | connected | reconnecting | failed`
Events: `batteryLevel | signalQuality | dropped | reconnected | reconnectAttemptFailed`
Reconnect: exponential backoff 1s→8s, auto-reapply layout on reconnect.

### WorkoutController actor

```swift
public actor WorkoutController {
    public init(substrate: any WorkoutHealthSubstrate, sessionID: UUID, clock: ...)
    public func start(activityType: SportType = .running) async throws -> WorkoutState
    public func pause() async throws
    public func resume() async throws
    public func end() async throws -> WorkoutSummary
    public func reportGlassesSignal(_ signal: GlassesConnectivitySignal)
    public nonisolated let states: AsyncStream<WorkoutState>
    public nonisolated let metrics: AsyncStream<WorkoutMetric>
}
```

- `reportGlassesSignal(.disconnected)` does NOT pause the workout (D4 enforcement).
- `WorkoutHealthSubstrate` protocol wraps HKWorkoutSession for testability.

---

## Current Version: v0.5.0

**Shipped 2026-05-20.** Strava mobile OAuth integration.

### v0.5 Scope (delivered)
- Strava OAuth connect button on phone
- Mobile OAuth flow (dual-path: native Strava app + web fallback)
- Token exchange via Cloudflare Worker (`strava-auth-worker.jkrilov.workers.dev`)

### Backlog (not yet scheduled)
- Finish screen + glasses disconnect fix (connection drops on run end)
- Battery level from glasses → phone display (BLE 0x180F, 30s notify)
- HR zone brightness on HUD
- Gesture-driven layout switch
- App Attest (issue #80)

---

## Governance

- Decisions inbox: drop files in `.squad/decisions/inbox/{agent}-{slug}.md`; Scribe merges.
- Each agent only edits its own `history.md`.
- Reviewer rejections lock out original author — different agent must revise.
- Coordinator dispatches, never implements domain code.
